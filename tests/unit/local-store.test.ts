import { beforeEach, describe, expect, it } from 'vitest';
import { LocalStore, DEMO_USERS } from '@/data/local-store';
import { addRecipeToShoppingList, createPlan, addRecipeToPlan } from '@/data/actions';
import { assembleRecipeDetail } from '@/lib/recipe-view';
import type { Ingredient } from '@/lib/types';
import { demo } from './fixtures';

/**
 * O modo demonstração precisa se comportar como o banco real.
 * Estes testes repetem, no armazenamento local, os mesmos cenários de tests/db.
 */
const SLUG = 'pave-floresta-negra-com-creme-danete';
let store: LocalStore;
const code = async (p: Promise<unknown>) => p.then(() => 'ok', (e: { code?: string }) => e.code ?? 'erro');

async function publishPave() {
  store.persona = 'admin';
  const [recipe] = await store.list('recipes', { eq: { slug: SLUG } });
  for (const flag of await store.list('review_flags', { eq: { recipe_id: recipe.id } })) {
    await store.update('review_flags', { id: flag.id }, { resolved_at: new Date().toISOString(), resolved_by: DEMO_USERS.admin.id });
  }
  await store.update('recipes', { id: recipe.id }, { status: 'approved' });
  await store.update('source_documents', { id: recipe.source_document_id! }, { commercial_permission: 'confirmed' });
  await store.update('recipes', { id: recipe.id }, { status: 'published' });
  return recipe;
}
async function activateSeason() {
  store.persona = 'admin';
  const [season] = await store.list('seasons');
  await store.update('seasons', { id: season.id }, {
    status: 'active', price_cents: 4990,
    access_starts_at: new Date(Date.now() - 86_400_000).toISOString(), access_ends_at: new Date(Date.now() + 30 * 86_400_000).toISOString(),
    sales_starts_at: new Date(Date.now() - 86_400_000).toISOString(), sales_ends_at: new Date(Date.now() + 30 * 86_400_000).toISOString(),
  });
}

beforeEach(() => {
  store = new LocalStore(async () => ({ version: 't', tables: {} }));
  store.loadSnapshot(demo.tables as never);
});

describe('modo demonstração: mesmas regras do banco', () => {
  it('administradora vê o catálogo inteiro; visitante e cliente só o que está publicado', async () => {
    store.persona = 'admin';
    expect(await store.list('recipes')).toHaveLength(62);
    expect((await store.rpc('my_access')).is_admin).toBe(true);
    store.persona = 'visitor';
    expect(await store.list('recipes')).toHaveLength(0);
    expect(await store.list('collections')).toHaveLength(6);
    expect(await code(store.list('recipe_ingredients'))).toBe('FORBIDDEN');
    expect(await code(store.list('meal_plans'))).toBe('FORBIDDEN');
    expect((await store.rpc('catalog_stats')).reduce((n, s) => n + s.in_preparation, 0)).toBe(62);
    store.persona = 'member';
    expect(await store.list('recipes')).toHaveLength(0);
    expect(await store.list('recipe_ingredients')).toHaveLength(0);
    expect(await store.list('source_documents')).toHaveLength(0);
  });

  it('bloqueia publicação com pendências, ficha incompleta ou fonte sem permissão', async () => {
    store.persona = 'admin';
    const [recipe] = await store.list('recipes', { eq: { slug: SLUG } });
    const warning = (await store.list('review_flags', { eq: { recipe_id: recipe.id } }))
      .find((flag) => flag.severity === 'warning' || flag.severity === 'blocker');
    expect(warning).toBeTruthy();
    await store.update('review_flags', { id: warning!.id }, { resolved_at: null });

    expect(await code(store.update('recipes', { id: recipe.id }, { status: 'published' }))).toBe('FLAGS_PENDING');
    const [stub] = await store.list('recipes', { eq: { content_state: 'catalogued' } });
    expect(stub).toBeTruthy();
    expect(await code(store.update('recipes', { id: stub.id }, { status: 'published' }))).toBe('CONTENT_REQUIRED');

    for (const flag of await store.list('review_flags', { eq: { recipe_id: recipe.id } })) {
      await store.update('review_flags', { id: flag.id }, { resolved_at: new Date().toISOString() });
    }
    expect(await code(store.update('recipes', { id: recipe.id }, { status: 'published' }))).toBe('PERMISSION_REQUIRED');
    await store.update('source_documents', { id: recipe.source_document_id! }, { commercial_permission: 'confirmed' });
    const [published] = await store.update('recipes', { id: recipe.id }, { status: 'published' });
    expect(published.status).toBe('published');
    expect(published.published_at).toBeTruthy();
    const actions = (await store.list('admin_audit_logs')).map((l) => l.action);
    expect(actions).toContain('source_documents.permission_changed');
    expect(actions.filter((a) => a === 'recipes.status_changed')).toHaveLength(1);
    // retirar a permissão tira a receita do ar
    await store.update('source_documents', { id: recipe.source_document_id! }, { commercial_permission: 'restricted' });
    expect((await store.list('recipes', { eq: { id: recipe.id } }))[0].status).toBe('pending_permission');
  });

  it('conteúdo premium exige receita publicada + temporada ativa + acesso', async () => {
    const recipe = await publishPave();
    store.persona = 'visitor';
    expect((await store.list('recipes')).map((r) => r.slug)).toEqual([SLUG]);
    expect(await store.list('source_document_refs')).toHaveLength(1);
    store.persona = 'member';
    expect(await store.list('recipe_ingredients')).toHaveLength(0); // temporada ainda em rascunho
    expect((await store.rpc('my_access')).has_access).toBe(false);
    expect(await code(store.insert('meal_plans', { title: 'Ceia' }))).toBe('ACCESS_REQUIRED');
    await activateSeason();
    store.persona = 'member';
    expect(await store.list('recipe_ingredients', { eq: { recipe_id: recipe.id } })).toHaveLength(12);
    expect((await store.rpc('my_access')).has_access).toBe(true);
  });

  it('clientes não alteram catálogo, acessos ou progresso de desafios', async () => {
    await publishPave();
    await activateSeason();
    store.persona = 'member';
    const [recipe] = await store.list('recipes');
    expect(await code(store.update('recipes', { id: recipe.id }, { title: 'x' }))).toBe('FORBIDDEN');
    expect(await code(store.insert('memberships', { user_id: DEMO_USERS.member.id, season_id: 'x' }))).toBe('FORBIDDEN');
    expect(await code(store.insert('user_challenges', { challenge_id: 'x' }))).toBe('FORBIDDEN');
    expect(await code(store.rpc('admin_usage_stats'))).toBe('FORBIDDEN');
    expect(await code(store.rpc('admin_set_role', { p_user: DEMO_USERS.member.id, p_role: 'admin' }))).toBe('FORBIDDEN');
    await store.update('profiles', { id: DEMO_USERS.member.id }, { full_name: 'Novo nome', role: 'admin' } as never);
    expect((await store.list('profiles'))[0]).toMatchObject({ full_name: 'Novo nome', role: 'customer' });
  });

  it('planejamento, lista de compras e desafios funcionam de ponta a ponta', async () => {
    const recipe = await publishPave();
    await activateSeason();
    store.persona = 'member';
    const plan = await createPlan(store, { title: 'Ceia em Família', occasion: 'natal', event_date: '2026-12-24', serve_time: '20:00', guests: 10 });
    expect(await store.list('plan_tasks', { eq: { plan_id: plan.id } })).toHaveLength(6);
    expect(await addRecipeToPlan(store, plan.id, recipe.id, 2)).toBe('added');
    expect(await addRecipeToPlan(store, plan.id, recipe.id, 2)).toBe('exists');

    const detail = assembleRecipeDetail(recipe, {
      components: await store.list('recipe_components'), ingredients: await store.list('recipe_ingredients'), steps: await store.list('recipe_steps'),
      stepIngredients: await store.list('recipe_step_ingredients'), timers: await store.list('recipe_step_timers'), notes: await store.list('recipe_notes'), tags: [],
    });
    const catalog = new Map<string, Ingredient>((await store.list('ingredients')).map((i) => [i.id, i]));
    expect(await addRecipeToShoppingList(store, detail, 2, catalog)).toBe(11);
    await addRecipeToShoppingList(store, detail, 2, catalog); // repetir não duplica
    const items = await store.list('shopping_items');
    expect(items).toHaveLength(11);
    expect(items.find((i) => i.name === 'Leite condensado')).toMatchObject({ quantity: 1200, unit: 'g' });

    const progress = await store.rpc('refresh_my_challenges');
    const challenges = await store.list('challenges');
    const done = progress.filter((p) => p.completed_at).map((p) => challenges.find((c) => c.id === p.challenge_id)?.slug);
    expect(done).toEqual(['organize-sua-ceia']);

    // dados pessoais não vazam entre pessoas
    store.persona = 'admin';
    expect(await store.list('meal_plans')).toHaveLength(0);
    expect(await store.list('shopping_items')).toHaveLength(0);
    expect((await store.rpc('admin_usage_stats')).plans).toBe(1);
  });

  it('simulação de pagamento só funciona com a venda aberta e libera o acesso', async () => {
    await publishPave();
    store.persona = 'admin';
    const [season] = await store.list('seasons');
    const [membership] = await store.list('memberships');
    await store.update('memberships', { id: membership.id }, { status: 'revoked', revoke_reason: 'teste', admin_locked: true });
    store.persona = 'member';
    expect(await code(store.simulateApprovedPayment())).toBe('SALES_CLOSED');
    await activateSeason();
    store.persona = 'member';
    expect((await store.rpc('my_access')).has_access).toBe(false);
    // acesso suspenso manualmente: não aceita pagamento
    expect(await code(store.simulateApprovedPayment())).toBe('ACCESS_LOCKED');
    store.persona = 'admin';
    await store.update('memberships', { id: membership.id }, { admin_locked: false });
    store.persona = 'member';
    await store.simulateApprovedPayment();
    expect(await code(store.simulateApprovedPayment())).toBe('ALREADY_MEMBER');
    expect(await store.rpc('my_access')).toMatchObject({ has_access: true, season_id: season.id, source: 'purchase' });
    expect(await store.list('orders')).toHaveLength(1);
  });
});
