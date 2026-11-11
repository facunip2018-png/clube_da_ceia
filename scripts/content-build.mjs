#!/usr/bin/env node
/**
 * Pipeline de conteúdo do Clube da Ceia Perfeita.
 *
 *   content/*.json  ──►  validação  ──►  linhas com UUID determinístico
 *                                         ├─ src/server/demo-data.generated.json  (modo demonstração)
 *                                         ├─ supabase/seed.sql                    (carga idempotente)
 *                                         └─ supabase/setup_completo.sql          (migrations + carga, para colar no SQL Editor)
 *
 * Uso:  node scripts/content-build.mjs          gera os arquivos
 *       node scripts/content-build.mjs --check  valida e falha se os arquivos gerados estiverem desatualizados
 *
 * Regras editoriais aplicadas aqui:
 *   • nada é inventado: receitas sem PDF entram apenas como "catalogued" (título + página a confirmar);
 *   • toda ficha estruturada guarda texto original, página e pontos de revisão;
 *   • a carga nunca sobrescreve o que foi editado no painel administrativo.
 */
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const CONTENT = join(ROOT, 'content');
const CHECK = process.argv.includes('--check');
const STAMP = '2026-11-10T00:00:00.000Z'; // carimbo fixo: saída determinística

// ------------------------------------------------------------------ utilidades
const NAMESPACE = '6f1d6c1e-52a7-4f0e-9d7b-c1ab0ce1a2d0';

function uuid5(name) {
  const ns = Buffer.from(NAMESPACE.replace(/-/g, ''), 'hex');
  const hash = createHash('sha1').update(ns).update(name, 'utf8').digest();
  const b = Buffer.from(hash.subarray(0, 16));
  b[6] = (b[6] & 0x0f) | 0x50;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = b.toString('hex');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

function slugify(text) {
  return String(text)
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/&/g, ' e ')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

const readJson = (file) => JSON.parse(readFileSync(file, 'utf8'));

function walk(dir) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .sort()
    .flatMap((name) => {
      const full = join(dir, name);
      return statSync(full).isDirectory() ? walk(full) : name.endsWith('.json') ? [full] : [];
    });
}

const errors = [];
const fail = (where, message) => errors.push(`${where}: ${message}`);
const oneOf = (where, field, value, allowed) => {
  if (!allowed.includes(value)) fail(where, `${field} = ${JSON.stringify(value)} (aceitos: ${allowed.join(', ')})`);
};

const ROLES = ['base', 'massa', 'esponja', 'recheio', 'cobertura', 'calda', 'creme', 'montagem', 'finalizacao', 'fritura', 'outro'];
const STATUSES = ['draft', 'review', 'approved', 'published', 'pending_permission', 'archived'];
const SEED_STATUSES = ['draft', 'review', 'pending_permission']; // conteúdo importado nunca nasce aprovado/publicado
const KINDS = ['recipe', 'component', 'variation'];
const SEVERITIES = ['info', 'warning', 'blocker'];
const SCALING = ['linear', 'manual', 'fixed'];
const TIMER_KINDS = ['cook', 'bake', 'chill', 'rest', 'other'];
const CATEGORIES = ['hortifruti', 'laticinios', 'mercearia', 'confeitaria', 'padaria', 'frios', 'carnes', 'bebidas', 'despensa', 'outros'];

// ------------------------------------------------------------------ leitura
const collectionsSrc = readJson(join(CONTENT, 'collections.json'));
const documentsSrc = readJson(join(CONTENT, 'documents.json'));
const ingredientsSrc = readJson(join(CONTENT, 'ingredients.json'));
const challengesSrc = readJson(join(CONTENT, 'challenges.json'));
const seasonsSrc = readJson(join(CONTENT, 'seasons.json'));
const catalogFiles = walk(join(CONTENT, 'catalog'));
const recipeFiles = walk(join(CONTENT, 'recipes'));

const T = {
  seasons: [], collections: [], source_documents: [], recipes: [], recipe_components: [], ingredients: [],
  recipe_ingredients: [], recipe_steps: [], recipe_step_ingredients: [], recipe_step_timers: [], recipe_notes: [],
  recipe_tags: [], recipe_compatibilities: [], review_flags: [], challenges: [],
};

// ------------------------------------------------------------------ tabelas de referência
for (const s of seasonsSrc) {
  oneOf(`seasons/${s.slug}`, 'status', s.status, ['draft', 'active', 'archived']);
  T.seasons.push({
    id: uuid5(`season:${s.slug}`), slug: s.slug, name: s.name, description: s.description ?? null,
    status: s.status, price_cents: s.price_cents ?? null, currency: s.currency ?? 'BRL',
    sales_starts_at: s.sales_starts_at ?? null, sales_ends_at: s.sales_ends_at ?? null,
    access_starts_at: s.access_starts_at ?? null, access_ends_at: s.access_ends_at ?? null,
    admin_notice: s.admin_notice ?? null,
  });
}

const collectionId = new Map();
for (const c of collectionsSrc) {
  oneOf(`collections/${c.slug}`, 'experience', c.experience, ['catalog', 'builder']);
  if (collectionId.has(c.slug)) fail(`collections/${c.slug}`, 'slug duplicado');
  const id = uuid5(`collection:${c.slug}`);
  collectionId.set(c.slug, id);
  T.collections.push({
    id, slug: c.slug, name: c.name, description: c.description ?? null, cover_image: c.cover_image ?? null,
    experience: c.experience, position: c.position ?? 0, is_visible: c.is_visible ?? true, admin_notice: c.admin_notice ?? null,
  });
}

const documentBySlug = new Map();
for (const d of documentsSrc) {
  const where = `documents/${d.slug}`;
  if (documentBySlug.has(d.slug)) fail(where, 'slug duplicado');
  if (!collectionId.has(d.collection)) fail(where, `coleção inexistente: ${d.collection}`);
  oneOf(where, 'file_status', d.file_status, ['not_provided', 'awaiting_upload', 'received', 'stored']);
  oneOf(where, 'commercial_permission', d.commercial_permission, ['unknown', 'confirmed', 'restricted', 'denied']);
  if (d.commercial_permission === 'confirmed') {
    fail(where, 'a permissão comercial só pode ser confirmada por um administrador, no painel (nunca pelo arquivo de conteúdo)');
  }
  const row = {
    id: uuid5(`document:${d.slug}`), slug: d.slug, collection_id: collectionId.get(d.collection) ?? null, title: d.title,
    author: d.author ?? null, publisher: d.publisher ?? null, file_name: d.file_name ?? null, language: d.language ?? 'pt-BR',
    page_count: d.page_count ?? null, file_status: d.file_status, storage_path: null, sha256: d.sha256 ?? null,
    commercial_permission: d.commercial_permission, permission_notes: d.permission_notes ?? null,
    measurement_notes: d.measurement_notes ?? null, import_notes: d.import_notes ?? null, toc: d.toc ?? [],
  };
  documentBySlug.set(d.slug, row);
  T.source_documents.push(row);
}

const ingredientId = new Map();
for (const i of ingredientsSrc) {
  const where = `ingredients/${i.slug}`;
  if (ingredientId.has(i.slug)) fail(where, 'slug duplicado');
  oneOf(where, 'category', i.category, CATEGORIES);
  const id = uuid5(`ingredient:${i.slug}`);
  ingredientId.set(i.slug, id);
  T.ingredients.push({ id, slug: i.slug, name: i.name, category: i.category, is_shoppable: i.is_shoppable ?? true });
}

challengesSrc.forEach((c, index) => {
  const where = `challenges/${c.slug}`;
  oneOf(where, 'rule_type', c.rule_type, ['cook_any', 'cook_in_collection', 'create_plan', 'complete_plan', 'shopping_done', 'favorites', 'chef_chat', 'manual']);
  if (c.rule_type === 'cook_in_collection' && !collectionId.has(c.rule_config?.collection_slug)) {
    fail(where, `coleção inexistente em rule_config: ${c.rule_config?.collection_slug}`);
  }
  T.challenges.push({
    id: uuid5(`challenge:${c.slug}`), slug: c.slug, season_id: null, title: c.title, description: c.description ?? null,
    icon: c.icon ?? null, points: c.points ?? 10, badge_name: c.badge_name ?? null, badge_tier: c.badge_tier ?? null,
    rule_type: c.rule_type, rule_config: c.rule_config ?? {}, allows_photo: c.allows_photo ?? true,
    is_active: c.is_active ?? true, position: index + 1,
  });
});

// ------------------------------------------------------------------ pontos de revisão
function addFlag(key, { recipeId = null, documentId = null, entity, entityId = null, field = null, flag, page = null }) {
  oneOf(`flag ${key}`, 'severity', flag.severity ?? 'warning', SEVERITIES);
  T.review_flags.push({
    id: uuid5(`flag:${key}`), recipe_id: recipeId, source_document_id: documentId, entity, entity_id: entityId,
    field, severity: flag.severity ?? 'warning', message: flag.message, source_page: flag.page ?? page ?? null,
  });
}
const needsReview = (flag) => Boolean(flag && (flag.severity ?? 'warning') !== 'info');

// ------------------------------------------------------------------ fichas estruturadas
const recipeBySlug = new Map();
const structuredSlugs = new Set();

function checkPage(where, page, doc) {
  if (page == null) return;
  if (!Number.isInteger(page) || page < 1) fail(where, `página inválida: ${page}`);
  else if (doc?.page_count && page > doc.page_count) fail(where, `página ${page} além das ${doc.page_count} páginas do documento`);
}

for (const file of recipeFiles) {
  const r = readJson(file);
  const where = relative(ROOT, file);
  const doc = documentBySlug.get(r.document);
  if (!r.slug || r.slug !== slugify(r.slug)) fail(where, `slug inválido: ${r.slug}`);
  if (recipeBySlug.has(r.slug)) fail(where, `slug duplicado: ${r.slug}`);
  if (!collectionId.has(r.collection)) fail(where, `coleção inexistente: ${r.collection}`);
  if (!doc) fail(where, `documento de origem inexistente: ${r.document}`);
  if (doc && !['received', 'stored'].includes(doc.file_status)) {
    fail(where, `ficha estruturada exige documento recebido (file_status de ${doc.slug} = ${doc.file_status})`);
  }
  oneOf(where, 'kind', r.kind ?? 'recipe', KINDS);
  oneOf(where, 'status', r.status, SEED_STATUSES);
  if (!r.source_pages?.start) fail(where, 'source_pages.start é obrigatório em fichas estruturadas');
  if (!Array.isArray(r.components) || r.components.length === 0) fail(where, 'a ficha precisa de pelo menos uma parte (components)');

  const recipeId = uuid5(`recipe:${r.slug}`);
  const y = r.yield ?? {};
  const t = r.times ?? {};
  [r.source_pages?.start, r.source_pages?.end, ...(r.source_pages?.extra ?? []), y.page].forEach((p) => checkPage(where, p, doc));

  const recipeRow = {
    id: recipeId, slug: r.slug, collection_id: collectionId.get(r.collection), source_document_id: doc?.id ?? null,
    kind: r.kind ?? 'recipe', component_role: r.component_role ?? null, flavor: r.flavor ?? null, title: r.title,
    original_title: r.original_title ?? null, original_language: r.language ?? doc?.language ?? 'pt-BR',
    translation_status: r.translation_status ?? 'not_needed', description: r.description ?? null,
    cover_image: r.cover_image ?? null, difficulty: r.difficulty ?? null,
    yield_quantity: y.quantity ?? null, yield_unit: y.unit ?? null, yield_unit_plural: y.unit_plural ?? null,
    yield_detail: y.detail ?? null, yield_text: y.text ?? null, servings: r.servings ?? null,
    prep_minutes: t.prep_minutes ?? null, cook_minutes: t.cook_minutes ?? null, bake_minutes: t.bake_minutes ?? null,
    chill_minutes: t.chill_minutes ?? null, rest_minutes: t.rest_minutes ?? null, chill_is_minimum: t.chill_is_minimum ?? false,
    measure_note: r.measure_note ?? null, source_page_start: r.source_pages?.start ?? null,
    source_page_end: r.source_pages?.end ?? null, source_pages_extra: r.source_pages?.extra ?? [],
    page_ref_verified: r.page_ref_verified ?? false, content_state: 'structured', status: r.status,
    position: r.position ?? 0, is_featured: r.is_featured ?? false,
  };
  recipeBySlug.set(r.slug, recipeRow);
  structuredSlugs.add(r.slug);
  T.recipes.push(recipeRow);

  for (const tag of r.tags ?? []) {
    T.recipe_tags.push({ id: uuid5(`tag:${r.slug}/${tag}`), recipe_id: recipeId, tag });
  }

  // 1ª passada: partes e ingredientes (para resolver referências das etapas)
  const componentIds = new Map();
  const riIds = new Map(); // "parte/chave" -> id
  const components = r.components ?? [];
  components.forEach((c, ci) => {
    const cw = `${where} › ${c.key}`;
    if (!c.key || componentIds.has(c.key)) fail(cw, 'chave de parte ausente ou duplicada');
    oneOf(cw, 'role', c.role, ROLES);
    const componentId = uuid5(`component:${r.slug}/${c.key}`);
    componentIds.set(c.key, componentId);
    (c.pages ?? []).forEach((p) => checkPage(cw, p, doc));
    T.recipe_components.push({
      id: componentId, recipe_id: recipeId, linked_recipe_id: null, role: c.role, title: c.title,
      original_title: c.original_title ?? null, description: c.description ?? null, multiplier: c.multiplier ?? 1,
      position: ci + 1, source_page_start: c.pages?.[0] ?? null, source_page_end: c.pages?.[1] ?? c.pages?.[0] ?? null,
    });
    if (c.flag) addFlag(`${r.slug}/component/${c.key}`, { recipeId, entity: 'component', entityId: componentId, flag: c.flag, page: c.pages?.[0] });

    (c.ingredients ?? []).forEach((ing, ii) => {
      const iw = `${cw} › ingrediente ${ing.key}`;
      const ref = `${c.key}/${ing.key}`;
      if (!ing.key || riIds.has(ref)) fail(iw, 'chave de ingrediente ausente ou duplicada');
      if (ing.ingredient && !ingredientId.has(ing.ingredient)) fail(iw, `ingrediente não cadastrado em content/ingredients.json: ${ing.ingredient}`);
      oneOf(iw, 'scaling', ing.scaling ?? 'linear', SCALING);
      if (ing.quantity == null && !ing.quantity_text) fail(iw, 'sem quantidade numérica: informe quantity_text (ex.: "a gosto", "quantidade não informada")');
      if (ing.quantity != null && (typeof ing.quantity !== 'number' || ing.quantity < 0)) fail(iw, `quantidade inválida: ${ing.quantity}`);
      if (ing.quantity != null && !ing.unit) fail(iw, 'quantidade numérica exige unidade');
      if (!ing.original) fail(iw, 'texto original (original) é obrigatório');
      checkPage(iw, ing.page, doc);
      const id = uuid5(`ri:${r.slug}/${ref}`);
      riIds.set(ref, id);
      T.recipe_ingredients.push({
        id, recipe_id: recipeId, component_id: componentId, ingredient_id: ing.ingredient ? ingredientId.get(ing.ingredient) ?? null : null,
        position: ii + 1, quantity: ing.quantity ?? null, quantity_max: ing.quantity_max ?? null, unit: ing.unit ?? null,
        quantity_text: ing.quantity_text ?? null, display_name: ing.name, preparation: ing.preparation ?? null,
        household_note: ing.household_note ?? null, scaling: ing.scaling ?? 'linear', is_optional: ing.is_optional ?? false,
        original_text: ing.original ?? null, source_page: ing.page ?? null, needs_review: needsReview(ing.flag),
      });
      if (ing.flag) addFlag(`${r.slug}/ingredient/${ref}`, { recipeId, entity: 'ingredient', entityId: id, field: 'quantity', flag: ing.flag, page: ing.page });
    });
  });

  // 2ª passada: etapas, temporizadores e o que cada etapa usa
  components.forEach((c) => {
    const componentId = componentIds.get(c.key);
    if (!c.steps?.length && !c.linked) fail(`${where} › ${c.key}`, 'parte sem etapas');
    (c.steps ?? []).forEach((s, si) => {
      const sw = `${where} › ${c.key} › etapa ${si + 1}`;
      if (!s.text) fail(sw, 'texto da etapa ausente');
      if (!s.original) fail(sw, 'texto original (original) é obrigatório');
      checkPage(sw, s.page, doc);
      const stepId = uuid5(`step:${r.slug}/${c.key}/${si + 1}`);
      T.recipe_steps.push({
        id: stepId, recipe_id: recipeId, component_id: componentId, position: si + 1, instruction: s.text,
        original_text: s.original ?? null, tip: s.tip ?? null, source_page: s.page ?? null, needs_review: needsReview(s.flag),
      });
      if (s.flag) addFlag(`${r.slug}/step/${c.key}/${si + 1}`, { recipeId, entity: 'step', entityId: stepId, field: 'instruction', flag: s.flag, page: s.page });

      let pos = 0;
      for (const use of s.uses ?? []) {
        const ref = use.includes('/') ? use : `${c.key}/${use}`;
        if (!riIds.has(ref)) { fail(sw, `"uses" aponta para ingrediente inexistente: ${use}`); continue; }
        T.recipe_step_ingredients.push({
          id: uuid5(`si:${r.slug}/${c.key}/${si + 1}/i/${ref}`), recipe_id: recipeId, step_id: stepId,
          recipe_ingredient_id: riIds.get(ref), component_id: null, position: ++pos,
        });
      }
      for (const use of s.uses_components ?? []) {
        if (!componentIds.has(use)) { fail(sw, `"uses_components" aponta para parte inexistente: ${use}`); continue; }
        T.recipe_step_ingredients.push({
          id: uuid5(`si:${r.slug}/${c.key}/${si + 1}/c/${use}`), recipe_id: recipeId, step_id: stepId,
          recipe_ingredient_id: null, component_id: componentIds.get(use), position: ++pos,
        });
      }
      (s.timers ?? []).forEach((tm, ti) => {
        const tw = `${sw} › temporizador ${ti + 1}`;
        if (!Number.isInteger(tm.seconds) || tm.seconds <= 0) fail(tw, `duração inválida: ${tm.seconds}`);
        oneOf(tw, 'kind', tm.kind ?? 'cook', TIMER_KINDS);
        if (!tm.original) fail(tw, 'trecho original que informa o tempo é obrigatório (não inferir tempos)');
        const timerId = uuid5(`timer:${r.slug}/${c.key}/${si + 1}/${ti + 1}`);
        T.recipe_step_timers.push({
          id: timerId, recipe_id: recipeId, step_id: stepId, label: tm.label, duration_seconds: tm.seconds,
          kind: tm.kind ?? 'cook', is_minimum: tm.is_minimum ?? false, temperature_c: tm.temperature_c ?? null,
          original_text: tm.original ?? null, needs_review: needsReview(tm.flag), position: ti + 1,
        });
        if (tm.flag) addFlag(`${r.slug}/timer/${c.key}/${si + 1}/${ti + 1}`, { recipeId, entity: 'timer', entityId: timerId, field: 'duration_seconds', flag: tm.flag, page: s.page });
      });
    });
  });

  // dicas, observações e equipamentos
  const addNotes = (list, kind) =>
    (list ?? []).forEach((n, ni) => {
      const id = uuid5(`note:${r.slug}/${kind}/${ni + 1}`);
      const body = kind === 'equipment' ? n.name : n.text;
      if (!body) fail(`${where} › ${kind} ${ni + 1}`, 'texto ausente');
      checkPage(`${where} › ${kind} ${ni + 1}`, n.page, doc);
      T.recipe_notes.push({
        id, recipe_id: recipeId, kind, title: n.title ?? null, body, original_text: n.original ?? null,
        source_page: n.page ?? null, position: ni + 1,
      });
      if (n.flag) addFlag(`${r.slug}/note/${kind}/${ni + 1}`, { recipeId, entity: 'note', entityId: id, field: 'body', flag: n.flag, page: n.page });
    });
  addNotes(r.tips, 'tip');
  addNotes(r.notes, 'note');
  addNotes(r.equipment, 'equipment');

  (r.flags ?? []).forEach((f, fi) => {
    if (!f.message) fail(`${where} › flags[${fi}]`, 'mensagem ausente');
    addFlag(`${r.slug}/recipe/${f.field ?? fi}`, { recipeId, entity: 'recipe', entityId: recipeId, field: f.field ?? null, flag: f });
  });
}

// ------------------------------------------------------------------ catálogo (títulos sem ficha)
for (const file of catalogFiles) {
  const cat = readJson(file);
  const where = relative(ROOT, file);
  const doc = documentBySlug.get(cat.document);
  if (!collectionId.has(cat.collection)) fail(where, `coleção inexistente: ${cat.collection}`);
  if (!doc) fail(where, `documento inexistente: ${cat.document}`);
  oneOf(where, 'status', cat.status, SEED_STATUSES);

  const created = [];
  (cat.entries ?? []).forEach((e, index) => {
    const slug = e.slug ?? slugify(e.title);
    const kind = e.kind ?? cat.kind ?? 'recipe';
    oneOf(`${where} › ${e.title}`, 'kind', kind, KINDS);
    if (e.role) oneOf(`${where} › ${e.title}`, 'role', e.role, ROLES);
    if (structuredSlugs.has(slug)) return; // a ficha estruturada substitui a entrada de catálogo
    if (recipeBySlug.has(slug)) { fail(`${where} › ${e.title}`, `slug duplicado: ${slug}`); return; }
    const id = uuid5(`recipe:${slug}`);
    const row = {
      id, slug, collection_id: collectionId.get(cat.collection), source_document_id: doc?.id ?? null, kind,
      component_role: e.role ?? null, flavor: e.flavor ?? null, title: e.title, original_title: e.original_title ?? null,
      original_language: cat.original_language ?? doc?.language ?? 'pt-BR',
      translation_status: cat.translation_status ?? 'not_needed', description: null, cover_image: null, difficulty: null,
      yield_quantity: null, yield_unit: null, yield_unit_plural: null, yield_detail: null, yield_text: null, servings: null,
      prep_minutes: null, cook_minutes: null, bake_minutes: null, chill_minutes: null, rest_minutes: null,
      chill_is_minimum: false, measure_note: null, source_page_start: e.page ?? null, source_page_end: null,
      source_pages_extra: [], page_ref_verified: false, content_state: 'catalogued', status: cat.status,
      position: e.position ?? index + 1, is_featured: false,
    };
    recipeBySlug.set(slug, row);
    T.recipes.push(row);
    created.push({ row, entry: e });
    if (e.note) {
      addFlag(`${slug}/recipe/catalog-note`, { recipeId: id, entity: 'recipe', entityId: id, field: 'source_page_start', flag: { severity: 'info', message: e.note } });
    }
  });

  if (doc && cat.page_ref_origin) {
    addFlag(`document/${doc.slug}/page-refs`, {
      documentId: doc.id, entity: 'document', entityId: doc.id, field: 'toc',
      flag: { severity: 'warning', message: `Títulos e páginas desta coleção: ${cat.page_ref_origin}. Nenhuma ficha foi estruturada sem o PDF.` },
    });
  }

  if (cat.compatibilities?.rule === 'same_flavor') {
    const bases = created.filter((c) => c.row.component_role === 'base');
    const fillings = created.filter((c) => c.row.kind === 'variation');
    for (const base of bases) {
      for (const filling of fillings.filter((f) => f.row.flavor === base.row.flavor)) {
        T.recipe_compatibilities.push({
          id: uuid5(`compat:${base.row.slug}/${filling.row.slug}`), recipe_id: base.row.id, compatible_recipe_id: filling.row.id,
          relation: 'recheio', source_page: null, verified: cat.compatibilities.verified === true, note: cat.compatibilities.note ?? null,
        });
      }
    }
    if (doc && cat.compatibilities.note) {
      addFlag(`document/${doc.slug}/compat`, {
        documentId: doc.id, entity: 'document', entityId: doc.id, field: 'compatibilities',
        flag: { severity: 'warning', message: cat.compatibilities.note },
      });
    }
  }
}

if (errors.length) {
  console.error(`\n✖ Conteúdo inválido (${errors.length} problema${errors.length > 1 ? 's' : ''}):\n`);
  for (const e of errors) console.error('  • ' + e);
  process.exit(1);
}

// ------------------------------------------------------------------ saída 1: dados do modo demonstração
const EXTRA_DEFAULTS = {
  source_documents: { permission_confirmed_by: null, permission_confirmed_at: null },
  recipes: { reviewed_by: null, reviewed_at: null, published_at: null },
  review_flags: { resolved_at: null, resolved_by: null, resolution_note: null },
};
const demo = { tables: {} };
for (const [table, rows] of Object.entries(T)) {
  demo.tables[table] = rows.map((row) => ({ ...row, ...(EXTRA_DEFAULTS[table] ?? {}), created_at: STAMP, updated_at: STAMP }));
}
const demoJson = JSON.stringify(demo, null, 1) + '\n';

// ------------------------------------------------------------------ saída 2: seed.sql
function lit(value) {
  if (value === null || value === undefined) return 'null';
  if (typeof value === 'number') return Number.isFinite(value) ? String(value) : 'null';
  if (typeof value === 'boolean') return value ? 'true' : 'false';
  if (Array.isArray(value) && value.every((v) => Number.isInteger(v))) return `'{${value.join(',')}}'::integer[]`;
  if (typeof value === 'object') return `'${JSON.stringify(value).replace(/'/g, "''")}'::jsonb`;
  return `'${String(value).replace(/'/g, "''")}'`;
}
const JSONB_COLUMNS = new Set(['toc', 'rule_config']);
function insertSql(table, rows, conflict, indent = '') {
  if (!rows.length) return '';
  const cols = Object.keys(rows[0]);
  const values = rows
    .map((row) => `${indent}  (${cols.map((c) => (JSONB_COLUMNS.has(c) ? `'${JSON.stringify(row[c]).replace(/'/g, "''")}'::jsonb` : lit(row[c]))).join(', ')})`)
    .join(',\n');
  return `${indent}insert into public.${table} (${cols.join(', ')}) values\n${values}\n${indent}${conflict};\n`;
}

const byRecipe = (table, recipeId) => T[table].filter((row) => row.recipe_id === recipeId);
const structured = T.recipes.filter((r) => r.content_state === 'structured');
const stubs = T.recipes.filter((r) => r.content_state === 'catalogued');
const recipeCols = Object.keys(T.recipes[0]).filter((c) => !['id', 'slug'].includes(c));

let seed = `-- =====================================================================
-- Clube da Ceia Perfeita — carga de conteúdo (GERADO por scripts/content-build.mjs)
-- Não edite à mão: altere os arquivos em content/ e rode \`npm run content:build\`.
--
-- A carga é idempotente e conservadora:
--   • linhas novas são inseridas; linhas existentes NÃO são sobrescritas
--     (o que foi ajustado no painel administrativo prevalece);
--   • exceção 1: receita que ainda é só "catalogued" (título) recebe a ficha
--     estruturada quando o PDF correspondente é importado;
--   • exceção 2: documento que estava aguardando arquivo passa a "received".
--   • todo conteúdo entra como rascunho/revisão: nada nasce publicado.
-- =====================================================================
begin;

-- Temporadas (preço e datas são definidos pelo administrador)
${insertSql('seasons', T.seasons, 'on conflict (slug) do nothing')}
-- Coleções
${insertSql('collections', T.collections, 'on conflict (slug) do nothing')}
-- Documentos de origem
${insertSql('source_documents', T.source_documents, `on conflict (slug) do update set
  file_status = excluded.file_status, page_count = excluded.page_count, sha256 = excluded.sha256,
  author = coalesce(public.source_documents.author, excluded.author),
  publisher = coalesce(public.source_documents.publisher, excluded.publisher),
  toc = excluded.toc, import_notes = excluded.import_notes
  where public.source_documents.file_status in ('not_provided', 'awaiting_upload')
    and excluded.file_status in ('received', 'stored')`)}
-- Ingredientes (catálogo para a lista de compras)
${insertSql('ingredients', T.ingredients, 'on conflict (slug) do nothing')}
-- Desafios
${insertSql('challenges', T.challenges, 'on conflict (slug) do nothing')}
-- Receitas catalogadas (título + página a confirmar; sem ficha)
${insertSql('recipes', stubs, 'on conflict (slug) do nothing')}
-- Receitas com ficha estruturada
${insertSql('recipes', structured, `on conflict (slug) do update set
  ${recipeCols.map((c) => `${c} = excluded.${c}`).join(', ')}
  where public.recipes.content_state = 'catalogued'`)}
`;

for (const r of structured) {
  const blocks = [
    insertSql('recipe_components', byRecipe('recipe_components', r.id), 'on conflict (id) do nothing', '    '),
    insertSql('recipe_ingredients', byRecipe('recipe_ingredients', r.id), 'on conflict (id) do nothing', '    '),
    insertSql('recipe_steps', byRecipe('recipe_steps', r.id), 'on conflict (id) do nothing', '    '),
    insertSql('recipe_step_ingredients', byRecipe('recipe_step_ingredients', r.id), 'on conflict (id) do nothing', '    '),
    insertSql('recipe_step_timers', byRecipe('recipe_step_timers', r.id), 'on conflict (id) do nothing', '    '),
    insertSql('recipe_notes', byRecipe('recipe_notes', r.id), 'on conflict (id) do nothing', '    '),
    insertSql('recipe_tags', byRecipe('recipe_tags', r.id), 'on conflict (recipe_id, tag) do nothing', '    '),
    insertSql('review_flags', byRecipe('review_flags', r.id), 'on conflict (id) do nothing', '    '),
  ].filter(Boolean);
  seed += `
-- Ficha: ${r.title}
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = ${lit(r.id)})
     and not exists (select 1 from public.recipe_ingredients where recipe_id = ${lit(r.id)})
     and not exists (select 1 from public.recipe_steps where recipe_id = ${lit(r.id)}) then
${blocks.join('')}  end if;
end $ficha$;
`;
}

const stubIds = new Set(stubs.map((r) => r.id));
const otherFlags = T.review_flags.filter((f) => !f.recipe_id || stubIds.has(f.recipe_id));
seed += `
-- Combinações do montador (a confirmar no PDF)
${insertSql('recipe_compatibilities', T.recipe_compatibilities, 'on conflict (recipe_id, compatible_recipe_id) do nothing') || '-- (nenhuma)\n'}
-- Pontos de revisão de documentos e de itens catalogados
${insertSql('review_flags', otherFlags, 'on conflict (id) do nothing') || '-- (nenhum)\n'}
commit;
`;

// ------------------------------------------------------------------ saída 3: setup_completo.sql
const migrationsDir = join(ROOT, 'supabase', 'migrations');
const migrations = existsSync(migrationsDir) ? readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort() : [];
let setup = `-- =====================================================================
-- Clube da Ceia Perfeita — instalação completa do banco (GERADO)
-- Cole este arquivo inteiro no SQL Editor do Supabase de um projeto NOVO e execute uma vez.
-- Conteúdo: ${migrations.length} migrations + carga inicial (supabase/seed.sql).
-- Para projetos que já rodaram as migrations, execute apenas supabase/seed.sql.
-- =====================================================================
`;
for (const m of migrations) {
  setup += `\n-- >>>>>>>>>> migrations/${m}\n` + readFileSync(join(migrationsDir, m), 'utf8').trimEnd() + '\n';
}
setup += `\n-- >>>>>>>>>> seed.sql\n` + seed;

// ------------------------------------------------------------------ gravação / conferência
const outputs = [
  [join(ROOT, 'src', 'server', 'demo-data.generated.json'), demoJson],
  [join(ROOT, 'supabase', 'seed.sql'), seed],
  [join(ROOT, 'supabase', 'setup_completo.sql'), setup],
];

let stale = 0;
for (const [file, content] of outputs) {
  const current = existsSync(file) ? readFileSync(file, 'utf8') : null;
  if (CHECK) {
    if (current !== content) {
      stale++;
      console.error(`✖ desatualizado: ${relative(ROOT, file)} (rode \`npm run content:build\`)`);
    }
  } else if (current !== content) {
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, content);
    console.log(`✔ gerado: ${relative(ROOT, file)}`);
  } else {
    console.log(`= sem mudanças: ${relative(ROOT, file)}`);
  }
}
if (stale) process.exit(1);

const count = (fn) => T.recipes.filter(fn).length;
console.log(
  `\nConteúdo validado: ${T.collections.length} coleções · ${T.source_documents.length} documentos · ` +
    `${T.recipes.length} itens de catálogo (${count((r) => r.content_state === 'structured')} com ficha estruturada, ` +
    `${count((r) => r.content_state === 'catalogued')} aguardando PDF) · ${T.recipe_ingredients.length} ingredientes de receita · ` +
    `${T.recipe_steps.length} etapas · ${T.recipe_step_timers.length} temporizadores · ${T.review_flags.length} pontos de revisão.`,
);
