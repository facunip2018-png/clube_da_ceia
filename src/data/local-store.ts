/**
 * Armazenamento do MODO DEMONSTRAÇÃO (sem servidor).
 *
 * Guarda os dados no navegador e reproduz as mesmas regras que o banco aplica em produção
 * (quem pode ler o quê, fluxo editorial, auditoria, desafios), para que a demonstração se
 * comporte como o app real. Em produção este arquivo não é usado: vale o RLS do Supabase.
 */
import type { Access, CatalogStat, Challenge, Recipe, RecipeStatus, Season, TableName, Tables, UserChallenge } from '@/lib/types';
import { AppError, checkRecipeTransition } from '@/lib/editorial';
import { refreshChallenges } from '@/lib/challenges';
import { saleAvailability } from '@/lib/season';
import { newId, readJson, safeStorage, writeJson } from '@/lib/safe-storage';
import type { DataStore, Query, Rpc, RpcName } from './store';

export type Persona = 'admin' | 'member' | 'visitor';

export const DEMO_USERS: Record<Exclude<Persona, 'visitor'>, { id: string; email: string; name: string }> = {
  admin: { id: '00000000-0000-4000-8000-00000000000a', email: 'admin@demo.clube', name: 'Administradora' },
  member: { id: '00000000-0000-4000-8000-00000000000b', email: 'cliente@demo.clube', name: 'Cliente do Clube' },
};

/* eslint-disable @typescript-eslint/no-explicit-any */
type Row = Record<string, any>;
type Db = Record<string, Row[]>;

const DB_KEY = 'ccp.demo.db.v1';

const PREMIUM = new Set(['recipe_components', 'recipe_ingredients', 'recipe_steps', 'recipe_step_ingredients', 'recipe_step_timers', 'recipe_notes', 'recipe_compatibilities']);
const PUBLIC = new Set(['seasons', 'collections', 'recipes', 'recipe_tags', 'challenges', 'source_document_refs']);
const ADMIN_ONLY = new Set(['source_documents', 'review_flags', 'admin_audit_logs', 'payment_transactions']);
const CATALOG = new Set(['seasons', 'collections', 'source_documents', 'recipes', 'recipe_components', 'ingredients', 'recipe_ingredients', 'recipe_steps', 'recipe_step_ingredients', 'recipe_step_timers', 'recipe_notes', 'recipe_tags', 'recipe_compatibilities', 'review_flags', 'challenges', 'support_materials']);
const OWNED = new Set(['recipe_favorites', 'meal_plans', 'plan_recipes', 'plan_tasks', 'shopping_lists', 'shopping_items', 'cooking_sessions', 'user_challenges', 'challenge_submissions', 'ai_conversations', 'ai_messages', 'orders', 'memberships']);
const SERVER_WRITTEN = new Set(['user_challenges', 'orders', 'payment_transactions', 'admin_audit_logs']);
const NEEDS_ACCESS = new Set(['meal_plans', 'cooking_sessions', 'ai_conversations', 'ai_messages']);
const AUDITED = new Set(['collections', 'source_documents', 'recipes', 'seasons', 'challenges', 'memberships', 'review_flags']);

const PARENT: Record<string, [string, string]> = {
  plan_recipes: ['meal_plans', 'plan_id'],
  plan_tasks: ['meal_plans', 'plan_id'],
  shopping_items: ['shopping_lists', 'list_id'],
  ai_messages: ['ai_conversations', 'conversation_id'],
};
const UNIQUE: Record<string, string[]> = {
  recipe_favorites: ['user_id', 'recipe_id'],
  plan_recipes: ['plan_id', 'recipe_id'],
  plan_tasks: ['plan_id', 'ref_key'],
  memberships: ['user_id', 'season_id'],
};
const CASCADE: Record<string, [string, string][]> = {
  meal_plans: [['plan_recipes', 'plan_id'], ['plan_tasks', 'plan_id']],
  shopping_lists: [['shopping_items', 'list_id']],
};

const defaults = (table: string, now: string): Row => {
  switch (table) {
    case 'meal_plans': return { season_id: null, occasion: 'natal', event_date: null, serve_time: null, guests: 8, notes: null, default_block_minutes: 30, status: 'active' };
    case 'plan_recipes': return { factor: 1, position: 0, notes: null, builder_selection: null };
    case 'plan_tasks': return { kind: 'custom', ref_key: null, due_at: null, is_done: false, done_at: null, position: 0 };
    case 'shopping_lists': return { plan_id: null, title: 'Minha lista', is_default: true };
    case 'shopping_items': return { ingredient_id: null, category: 'outros', quantity: null, unit: null, quantity_text: null, is_checked: false, checked_at: null, is_manual: false, quantity_edited: false, sources: [], note: null, position: 0 };
    case 'cooking_sessions': return { plan_id: null, factor: 1, current_step: 0, completed_steps: [], status: 'active', started_at: now, finished_at: null };
    case 'challenge_submissions': return { photo_path: null, note: null, status: 'submitted', reviewed_by: null, reviewed_at: null };
    case 'ai_conversations': return { title: null, recipe_id: null, archived_at: null };
    case 'ai_messages': return { grounded_recipe_ids: [], model: null, tokens_in: null, tokens_out: null };
    case 'memberships': return { status: 'active', source: 'courtesy', order_id: null, granted_by: null, granted_at: now, revoked_at: null, revoke_reason: null, admin_locked: false, expires_at: null };
    case 'review_flags': return { recipe_id: null, source_document_id: null, entity_id: null, field: null, severity: 'warning', source_page: null, resolved_at: null, resolved_by: null, resolution_note: null };
    case 'recipe_ingredients': return { component_id: null, ingredient_id: null, position: 0, quantity: null, quantity_max: null, unit: null, quantity_text: null, preparation: null, household_note: null, scaling: 'linear', is_optional: false, original_text: null, source_page: null, needs_review: false };
    case 'recipe_steps': return { component_id: null, position: 0, original_text: null, tip: null, source_page: null, needs_review: false };
    default: return {};
  }
};

const clone = <T>(value: T): T => JSON.parse(JSON.stringify(value));

export class LocalStore implements DataStore {
  readonly kind = 'demo' as const;
  private db: Db = {};
  private version = '';
  private ready: Promise<void> | null = null;
  persona: Persona = 'admin';

  constructor(private fetchCatalog: () => Promise<{ version: string; tables: Db }>) {}

  // ------------------------------------------------------------------ ciclo de vida
  init(): Promise<void> {
    this.ready ??= this.load();
    return this.ready;
  }

  private async load() {
    const stored = readJson<{ version: string; db: Db } | null>(DB_KEY, null);
    const catalog = await this.fetchCatalog();
    if (stored && stored.version === catalog.version) {
      this.db = stored.db;
    } else {
      // conteúdo novo: troca o catálogo e mantém os dados pessoais da demonstração
      this.db = { ...(stored?.db ?? {}) };
      for (const [table, rows] of Object.entries(catalog.tables)) this.db[table] = clone(rows);
    }
    this.version = catalog.version;
    this.bootstrapUsers();
    this.save();
  }

  /** Carrega um banco pronto (usado nos testes). */
  loadSnapshot(tables: Db) {
    this.db = clone(tables);
    this.bootstrapUsers();
    this.ready = Promise.resolve();
  }

  private bootstrapUsers() {
    const now = new Date().toISOString();
    const profiles = this.table('profiles');
    for (const [key, user] of Object.entries(DEMO_USERS)) {
      if (!profiles.some((p) => p.id === user.id)) {
        profiles.push({ id: user.id, email: user.email, full_name: user.name, avatar_url: null, role: key === 'admin' ? 'admin' : 'customer', preferences: {}, created_at: now, updated_at: now });
      }
    }
    // a cliente de demonstração já tem um acesso de cortesia: ele só vale quando a temporada for ativada
    const season = this.table('seasons')[0];
    if (season && !this.table('memberships').some((m) => m.user_id === DEMO_USERS.member.id && m.season_id === season.id)) {
      this.table('memberships').push({ id: newId(), user_id: DEMO_USERS.member.id, season_id: season.id, ...defaults('memberships', now), created_at: now, updated_at: now });
    }
  }

  private save() {
    writeJson(DB_KEY, { version: this.version, db: this.db });
  }

  /** Apaga tudo o que foi feito na demonstração. */
  static clear() {
    safeStorage.remove(DB_KEY);
  }

  // ------------------------------------------------------------------ identidade
  get userId(): string | null {
    return this.persona === 'visitor' ? null : DEMO_USERS[this.persona].id;
  }
  private isAdmin(): boolean {
    const id = this.userId;
    return Boolean(id && this.table('profiles').some((p) => p.id === id && p.role === 'admin'));
  }
  private hasAccess(): boolean {
    if (this.isAdmin()) return true;
    const id = this.userId;
    if (!id) return false;
    return Boolean(this.activeMembership(id));
  }
  private activeMembership(userId: string): { season: Season; membership: Row } | null {
    const now = Date.now();
    for (const membership of this.table('memberships')) {
      if (membership.user_id !== userId || membership.status !== 'active') continue;
      if (membership.expires_at && new Date(membership.expires_at).getTime() <= now) continue;
      const season = this.table('seasons').find((s) => s.id === membership.season_id) as Season | undefined;
      if (!season || season.status !== 'active' || !season.access_starts_at || !season.access_ends_at) continue;
      if (now >= new Date(season.access_starts_at).getTime() && now < new Date(season.access_ends_at).getTime()) return { season, membership };
    }
    return null;
  }

  // ------------------------------------------------------------------ leitura (equivalente ao RLS)
  private table(name: string): Row[] {
    return (this.db[name] ??= []);
  }
  private published(recipeId: string): boolean {
    return this.table('recipes').some((r) => r.id === recipeId && r.status === 'published');
  }

  private canRead(table: string, row: Row): boolean {
    const admin = this.isAdmin();
    switch (table) {
      case 'seasons': return admin || row.status === 'active';
      case 'collections': return admin || row.is_visible;
      case 'recipes': return admin || row.status === 'published';
      case 'recipe_tags': return admin || this.published(row.recipe_id);
      case 'challenges': return admin || row.is_active;
      case 'source_document_refs': return true;
      case 'support_materials': return admin || (this.hasAccess() && row.is_visible);
      case 'ingredients': return this.hasAccess();
      case 'profiles': return admin || row.id === this.userId;
      case 'challenge_submissions':
      case 'orders':
      case 'memberships': return admin || row.user_id === this.userId;
    }
    if (PREMIUM.has(table)) return admin || (this.hasAccess() && this.published(row.recipe_id));
    if (ADMIN_ONLY.has(table)) return admin;
    if (OWNED.has(table)) return row.user_id === this.userId;
    return false;
  }

  private rows(table: string): Row[] {
    if (table === 'source_document_refs') {
      return this.table('source_documents')
        .filter((d) => this.table('recipes').some((r) => r.source_document_id === d.id && r.status === 'published'))
        .map((d) => ({ id: d.id, title: d.title, author: d.author, publisher: d.publisher, language: d.language }));
    }
    return this.table(table);
  }

  private visible(table: string): Row[] {
    if (!PUBLIC.has(table) && !this.userId) {
      throw new AppError('FORBIDDEN', 'Entre na sua conta para continuar.');
    }
    return this.rows(table).filter((row) => this.canRead(table, row));
  }

  private static matches(row: Row, eq: Row = {}, within: Record<string, unknown[]> = {}): boolean {
    for (const [key, value] of Object.entries(eq)) if ((row[key] ?? null) !== value) return false;
    for (const [key, values] of Object.entries(within)) if (!values.includes(row[key])) return false;
    return true;
  }

  async list<K extends TableName>(table: K, query: Query<Tables[K]> = {}): Promise<Tables[K][]> {
    await this.init();
    let rows = this.visible(table).filter((row) => LocalStore.matches(row, query.eq as Row, query.in as Record<string, unknown[]>));
    for (const [column, direction] of [...(query.order ?? [])].reverse()) {
      const sign = direction === 'asc' ? 1 : -1;
      rows = [...rows].sort((a, b) => (a[column] === b[column] ? 0 : a[column] == null ? 1 : b[column] == null ? -1 : a[column] > b[column] ? sign : -sign));
    }
    if (query.limit) rows = rows.slice(0, query.limit);
    return clone(rows) as Tables[K][];
  }

  // ------------------------------------------------------------------ escrita
  private requireUser(): string {
    const id = this.userId;
    if (!id) throw new AppError('NOT_AUTHENTICATED', 'Entre na sua conta para continuar.');
    return id;
  }

  private assertCanWrite(table: string, action: 'insert' | 'update' | 'delete') {
    this.requireUser();
    if (CATALOG.has(table)) {
      if (!this.isAdmin()) throw new AppError('FORBIDDEN', 'Apenas administradores podem alterar o catálogo.');
      return;
    }
    if (SERVER_WRITTEN.has(table)) throw new AppError('FORBIDDEN', 'Este registro só é alterado pelo servidor.');
    if (table === 'memberships' && (!this.isAdmin() || action === 'delete')) throw new AppError('FORBIDDEN', 'Apenas administradores gerenciam acessos.');
    if (table === 'challenge_submissions' && action === 'update' && !this.isAdmin()) throw new AppError('FORBIDDEN', 'Apenas administradores moderam envios.');
    if (table === 'ai_messages' && action !== 'insert') throw new AppError('FORBIDDEN', 'O histórico do Chef não pode ser alterado.');
    if (table === 'ai_conversations' && action === 'delete') throw new AppError('FORBIDDEN', 'Conversas são arquivadas, não apagadas.');
    if (table === 'profiles' && action !== 'update') throw new AppError('FORBIDDEN', 'Perfis são criados no cadastro.');
    if (!OWNED.has(table) && table !== 'profiles') throw new AppError('FORBIDDEN', 'Tabela indisponível.');
  }

  private audit(action: string, entity: string, entityId: string, summary: string | null, oldData: Row | null, newData: Row | null) {
    const user = this.table('profiles').find((p) => p.id === this.userId);
    this.table('admin_audit_logs').push({
      id: newId(), actor_id: this.userId, actor_email: user?.email ?? null, action, entity, entity_id: entityId, summary,
      old_data: oldData, new_data: newData, created_at: new Date().toISOString(),
    });
  }

  async insert<K extends TableName>(table: K, values: Partial<Tables[K]> | Partial<Tables[K]>[]): Promise<Tables[K][]> {
    await this.init();
    this.assertCanWrite(table, 'insert');
    const userId = this.requireUser();
    const now = new Date().toISOString();
    const created: Row[] = [];

    for (const value of (Array.isArray(values) ? values : [values]) as Row[]) {
      const row: Row = { id: newId(), ...defaults(table, now), ...clone(value), created_at: now, updated_at: now };
      if (OWNED.has(table) && table !== 'memberships') row.user_id = userId; // ninguém grava em nome de outra pessoa
      if (table === 'memberships') {
        if (!['courtesy', 'admin'].includes(row.source)) throw new AppError('FORBIDDEN', 'Acesso por compra só é concedido pelo servidor.');
        row.granted_by = userId;
      }
      if (NEEDS_ACCESS.has(table) && !this.hasAccess()) {
        throw new AppError('ACCESS_REQUIRED', 'Este recurso faz parte do acesso da temporada.');
      }
      const parent = PARENT[table];
      if (parent && !this.table(parent[0]).some((p) => p.id === row[parent[1]] && p.user_id === userId)) {
        throw new AppError('FORBIDDEN', 'Você não tem permissão para esta ação.');
      }
      const unique = UNIQUE[table];
      if (unique && unique.every((k) => row[k] != null) && this.table(table).some((r) => unique.every((k) => r[k] === row[k]))) {
        throw new AppError('DUPLICATE', 'Este registro já existe.');
      }
      if (table === 'recipes' && !['draft', 'review'].includes(row.status ?? 'draft')) {
        throw new AppError('APPROVAL_REQUIRED', 'Receitas novas entram como rascunho ou em revisão.');
      }
      this.table(table).push(row);
      created.push(row);
      if (AUDITED.has(table) && table !== 'review_flags') this.audit(`${table}.created`, table, row.id, row.title ?? row.name ?? row.source ?? null, null, clone(row));
    }
    this.save();
    return clone(created) as Tables[K][];
  }

  private guardRecipe(recipe: Recipe, next: RecipeStatus): Partial<Recipe> {
    const document = this.table('source_documents').find((d) => d.id === recipe.source_document_id);
    const linked = this.table('recipe_components').filter((c) => c.recipe_id === recipe.id && c.linked_recipe_id);
    return checkRecipeTransition(recipe, next, {
      openFlags: this.table('review_flags').filter((f) => f.recipe_id === recipe.id && !f.resolved_at && f.severity !== 'info').length,
      permission: document?.commercial_permission ?? null,
      linkedUnpublished: linked.filter((c) => !this.published(c.linked_recipe_id)).length,
      userId: this.userId,
      now: new Date().toISOString(),
    });
  }

  async update<K extends TableName>(table: K, match: NonNullable<Query<Tables[K]>['eq']>, patch: Partial<Tables[K]>): Promise<Tables[K][]> {
    await this.init();
    this.assertCanWrite(table, 'update');
    const now = new Date().toISOString();
    const targets = this.visible(table).filter((row) => LocalStore.matches(row, match as Row));
    const updated: Row[] = [];

    for (const row of targets) {
      if (OWNED.has(table) && !this.isAdminTable(table) && row.user_id !== this.userId) continue;
      let change: Row = clone(patch as Row);
      delete change.id;
      delete change.created_at;
      if (OWNED.has(table) && table !== 'memberships') delete change.user_id;
      const before = clone(row);

      if (table === 'profiles') {
        if (row.id !== this.userId) continue;
        change = Object.fromEntries(Object.entries(change).filter(([k]) => ['full_name', 'avatar_url', 'preferences'].includes(k)));
      }
      if (table === 'recipes' && change.status && change.status !== row.status) {
        Object.assign(change, this.guardRecipe(row as Recipe, change.status));
      }
      if (table === 'source_documents' && change.commercial_permission && change.commercial_permission !== row.commercial_permission) {
        const confirmed = change.commercial_permission === 'confirmed';
        change.permission_confirmed_at = confirmed ? now : null;
        change.permission_confirmed_by = confirmed ? this.userId : null;
      }

      Object.assign(row, change, { updated_at: now });
      updated.push(row);

      if (table === 'source_documents' && before.commercial_permission !== row.commercial_permission) {
        // mesma cascata do banco: sem permissão confirmada, as receitas saem do ar
        for (const recipe of this.table('recipes').filter((r) => r.source_document_id === row.id)) {
          if (row.commercial_permission === 'confirmed' && recipe.status === 'pending_permission') {
            recipe.status = recipe.reviewed_at ? 'review' : 'draft';
          } else if (row.commercial_permission !== 'confirmed' && recipe.status === 'published') {
            recipe.status = 'pending_permission';
          }
        }
      }
      if (AUDITED.has(table)) this.auditUpdate(table, before, row);
    }
    this.save();
    return clone(updated) as Tables[K][];
  }

  private isAdminTable(table: string) {
    return this.isAdmin() && (table === 'memberships' || table === 'challenge_submissions');
  }

  private auditUpdate(table: string, before: Row, after: Row) {
    const changed = (key: string) => before[key] !== after[key];
    if (table === 'recipes' && changed('status')) {
      this.audit('recipes.status_changed', table, after.id, `${after.title}: ${before.status} → ${after.status}`, before, clone(after));
    } else if (table === 'source_documents' && changed('commercial_permission')) {
      this.audit('source_documents.permission_changed', table, after.id, `${after.title}: ${before.commercial_permission} → ${after.commercial_permission}`, before, clone(after));
    } else if (table === 'memberships' && changed('status')) {
      this.audit(`memberships.${after.status}`, table, after.id, after.revoke_reason ?? after.source, before, clone(after));
    } else if (table === 'review_flags') {
      if (changed('resolved_at')) this.audit(after.resolved_at ? 'review_flags.resolved' : 'review_flags.reopened', table, after.id, String(after.message).slice(0, 160), before, clone(after));
    } else {
      this.audit(`${table}.updated`, table, after.id, after.title ?? after.name ?? null, before, clone(after));
    }
  }

  async remove<K extends TableName>(table: K, match: NonNullable<Query<Tables[K]>['eq']>): Promise<void> {
    await this.init();
    this.assertCanWrite(table, 'delete');
    const targets = new Set(
      this.visible(table)
        .filter((row) => LocalStore.matches(row, match as Row))
        .filter((row) => !OWNED.has(table) || row.user_id === this.userId)
        .map((row) => row.id),
    );
    if (!targets.size) return;
    for (const row of this.table(table).filter((r) => targets.has(r.id))) {
      if (AUDITED.has(table) && table !== 'review_flags') this.audit(`${table}.deleted`, table, row.id, row.title ?? row.name ?? null, clone(row), null);
    }
    this.db[table] = this.table(table).filter((row) => !targets.has(row.id));
    for (const [child, key] of CASCADE[table] ?? []) {
      this.db[child] = this.table(child).filter((row) => !targets.has(row[key]));
    }
    if (table === 'meal_plans') {
      for (const row of [...this.table('shopping_lists'), ...this.table('cooking_sessions')]) if (targets.has(row.plan_id)) row.plan_id = null;
    }
    this.save();
  }

  // ------------------------------------------------------------------ funções do banco
  async rpc<N extends RpcName>(name: N, args?: Rpc[N]['args']): Promise<Rpc[N]['result']> {
    await this.init();
    const result = this.callRpc(name, args as Row | undefined);
    this.save();
    return clone(result) as Rpc[N]['result'];
  }

  private callRpc(name: RpcName, args?: Row): unknown {
    switch (name) {
      case 'my_access':
        return this.myAccess();
      case 'catalog_stats':
        return this.catalogStats();
      case 'refresh_my_challenges':
        return this.refreshMyChallenges();
      case 'admin_usage_stats':
        return this.usageStats();
      case 'admin_set_role': {
        if (!this.isAdmin()) throw new AppError('FORBIDDEN', 'Apenas administradores.');
        if (args?.p_user === this.userId && args?.p_role !== 'admin') throw new AppError('SELF_DEMOTION', 'Outro administrador precisa remover o seu acesso.');
        const profile = this.table('profiles').find((p) => p.id === args?.p_user);
        if (!profile) throw new AppError('USER_NOT_FOUND', 'Pessoa não encontrada.');
        const before = profile.role;
        profile.role = args?.p_role;
        if (before !== profile.role) this.audit('profiles.role_changed', 'profiles', profile.id, `${profile.email}: ${before} → ${profile.role}`, null, null);
        return null;
      }
    }
  }

  private myAccess(): Access {
    const id = this.userId;
    if (!id) return { authenticated: false, is_admin: false, has_access: false };
    const active = this.activeMembership(id);
    const admin = this.isAdmin();
    return {
      authenticated: true,
      is_admin: admin,
      has_access: admin || Boolean(active),
      season_id: active?.season.id ?? null,
      season_name: active?.season.name ?? null,
      access_until: active?.season.access_ends_at ?? null,
      source: active?.membership.source ?? null,
    };
  }

  private catalogStats(): CatalogStat[] {
    const recipes = this.table('recipes');
    return this.table('collections')
      .filter((c) => c.is_visible)
      .map((c) => {
        const own = recipes.filter((r) => r.collection_id === c.id);
        const published = (kind: string) => own.filter((r) => r.status === 'published' && r.kind === kind).length;
        return {
          collection_id: c.id,
          published_recipes: published('recipe'),
          published_components: published('component'),
          published_variations: published('variation'),
          in_preparation: own.filter((r) => ['draft', 'review', 'approved', 'pending_permission'].includes(r.status)).length,
        };
      });
  }

  private refreshMyChallenges(): UserChallenge[] {
    const userId = this.requireUser();
    const mine = (table: string) => this.table(table).filter((r) => r.user_id === userId);
    const collectionSlug = new Map(this.table('collections').map((c) => [c.id, c.slug as string]));
    const now = new Date();
    const existing = mine('user_challenges');
    const computed = refreshChallenges(this.table('challenges') as Challenge[], existing as UserChallenge[], {
      sessions: mine('cooking_sessions') as never,
      collectionSlugByRecipe: new Map(this.table('recipes').map((r) => [r.id, collectionSlug.get(r.collection_id) ?? ''])),
      plans: mine('meal_plans') as never,
      planRecipes: mine('plan_recipes') as never,
      planTasks: mine('plan_tasks') as never,
      lists: mine('shopping_lists') as never,
      items: mine('shopping_items') as never,
      favorites: mine('recipe_favorites') as never,
      userMessages: mine('ai_messages').filter((m) => m.role === 'user').length,
    }, now);
    for (const progress of computed) {
      const row = existing.find((e) => e.challenge_id === progress.challenge_id);
      if (row) Object.assign(row, progress, { updated_at: now.toISOString() });
      else this.table('user_challenges').push({ id: newId(), user_id: userId, ...progress, created_at: now.toISOString(), updated_at: now.toISOString() });
    }
    return mine('user_challenges') as UserChallenge[];
  }

  private usageStats(): Record<string, unknown> {
    if (!this.isAdmin()) throw new AppError('FORBIDDEN', 'Apenas administradores.');
    const count = (table: string, filter: (r: Row) => boolean = () => true) => this.table(table).filter(filter).length;
    const week = Date.now() - 7 * 86_400_000;
    const favorites = new Map<string, number>();
    for (const f of this.table('recipe_favorites')) favorites.set(f.recipe_id, (favorites.get(f.recipe_id) ?? 0) + 1);
    return {
      users: count('profiles'),
      active_memberships: count('memberships', (m) => m.status === 'active' && this.table('seasons').some((s) => s.id === m.season_id && s.status === 'active')),
      orders_approved: count('orders', (o) => o.status === 'approved'),
      orders_pending: count('orders', (o) => o.status === 'pending'),
      revenue_cents: this.table('orders').filter((o) => o.status === 'approved').reduce((sum, o) => sum + o.amount_cents, 0),
      plans: count('meal_plans'),
      cooking_sessions_finished: count('cooking_sessions', (s) => s.status === 'finished'),
      favorites: count('recipe_favorites'),
      shopping_items: count('shopping_items'),
      chef_messages: count('ai_messages', (m) => m.role === 'user'),
      chef_messages_7d: count('ai_messages', (m) => m.role === 'user' && new Date(m.created_at).getTime() > week),
      challenges_completed: count('user_challenges', (u) => Boolean(u.completed_at)),
      top_favorites: [...favorites.entries()]
        .map(([id, total]) => ({ title: this.table('recipes').find((r) => r.id === id)?.title ?? '—', total }))
        .sort((a, b) => b.total - a.total)
        .slice(0, 5),
    };
  }

  /**
   * SOMENTE DEMONSTRAÇÃO: simula o resultado de um pagamento aprovado, do jeito que o
   * servidor faria após o webhook do Mercado Pago (pedido aprovado → acesso liberado).
   */
  async simulateApprovedPayment(): Promise<void> {
    await this.init();
    const userId = this.requireUser();
    const season = this.table('seasons').find((s) => s.status === 'active') as Season | undefined;
    const sale = saleAvailability(season);
    if (!season || !sale.open) throw new AppError('SALES_CLOSED', sale.reason ?? 'Vendas indisponíveis.');
    const existing = this.table('memberships').find((m) => m.user_id === userId && m.season_id === season.id);
    if (existing?.status === 'active') throw new AppError('ALREADY_MEMBER', 'Você já tem o acesso desta temporada.');
    if (existing?.admin_locked) throw new AppError('ACCESS_LOCKED', 'Seu acesso a esta temporada foi suspenso pela administração. Fale com o suporte do Clube.');
    const now = new Date().toISOString();
    const order = {
      id: newId(), user_id: userId, season_id: season.id, status: 'approved', amount_cents: season.price_cents, currency: season.currency,
      provider: 'simulacao', provider_preference_id: null, provider_payment_id: `SIM-${Date.now()}`, paid_at: now, created_at: now, updated_at: now,
    };
    this.table('orders').push(order);
    const membership = this.table('memberships').find((m) => m.user_id === userId && m.season_id === season.id);
    if (membership) {
      if (!membership.admin_locked) Object.assign(membership, { status: 'active', source: 'purchase', order_id: order.id, revoked_at: null, revoke_reason: null, updated_at: now });
    } else {
      this.table('memberships').push({ id: newId(), user_id: userId, season_id: season.id, ...defaults('memberships', now), source: 'purchase', order_id: order.id, created_at: now, updated_at: now });
    }
    this.save();
  }
}
