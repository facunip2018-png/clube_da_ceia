/**
 * Teste de fumaça contra o projeto Supabase REAL (login, RLS, funções e Storage pela API pública).
 *
 *   SUPABASE_URL=https://xxxx.supabase.co SUPABASE_PUBLISHABLE_KEY=sb_publishable_... \
 *   TEST_ADMIN_EMAIL=... TEST_CUSTOMER_EMAIL=... TEST_PASSWORD=... npm run test:hosted
 *
 * Pré-requisitos: dois usuários de TESTE com a mesma senha (um com profiles.role = 'admin', outro comum,
 * sem acesso à temporada). Pode ser executado várias vezes: começa removendo as sobras da execução anterior.
 *
 * O teste só cria registros marcados como "zz-teste" e apaga o que consegue pela API. Ficam para
 * limpeza manual (SQL): a temporada e a membership de teste, as conversas do Chef e as linhas de
 * auditoria geradas — veja "Limpeza" em docs/TESTES.md. NÃO rode com usuários reais.
 */
import { createClient } from '@supabase/supabase-js';

const env = (name) => {
  const value = process.env[name];
  if (!value) {
    console.error(`Defina ${name} (veja o cabeçalho deste arquivo).`);
    process.exit(2);
  }
  return value;
};
const URL = env('SUPABASE_URL');
const KEY = env('SUPABASE_PUBLISHABLE_KEY');
const PASSWORD = env('TEST_PASSWORD');
const ADMIN_EMAIL = env('TEST_ADMIN_EMAIL');
const CUSTOMER_EMAIL = env('TEST_CUSTOMER_EMAIL');
/** SMOKE_KEEP=1 mantém a ficha, a temporada e o acesso de teste (para testar o app no navegador em seguida). */
const KEEP = process.env.SMOKE_KEEP === '1';

// Node < 22 não tem WebSocket nativo e o supabase-js recusa criar o cliente; este teste não usa Realtime.
const realtime = typeof WebSocket === 'undefined' ? { transport: class NoRealtime {} } : undefined;
const newClient = () => createClient(URL, KEY, { auth: { persistSession: false, autoRefreshToken: false }, ...(realtime ? { realtime } : {}) });
const anon = newClient();
const admin = newClient();
const customer = newClient();

let passed = 0;
const failures = [];
async function check(name, fn) {
  try {
    const detail = await fn();
    passed += 1;
    console.log(`✓ ${name}${detail ? ` — ${detail}` : ''}`);
  } catch (error) {
    failures.push(name);
    console.log(`✗ ${name} → ${error.message}`);
  }
}
const describeError = (error) => `${error.code ?? error.statusCode ?? error.status ?? ''} ${error.message ?? ''}`.trim();
/** Linhas devolvidas (falha se a API devolver erro). */
async function rows(promise) {
  const { data, error } = await promise;
  if (error) throw new Error(describeError(error));
  return data;
}
/** A operação DEVE ser recusada. */
async function denied(promise, pattern) {
  const { data, error } = await promise;
  if (!error) throw new Error(`esperava recusa, mas foi aceito (${JSON.stringify(data)?.slice(0, 80)})`);
  const text = describeError(error);
  if (pattern && !pattern.test(text)) throw new Error(`recusado, mas com erro inesperado: ${text}`);
  return text.slice(0, 70);
}
function equal(actual, expected, label) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${label}: esperado ${JSON.stringify(expected)}, veio ${JSON.stringify(actual)}`);
  }
}
const one = (list, label) => {
  if (!list || list.length !== 1) throw new Error(`${label}: esperava 1 linha, vieram ${list?.length ?? 0}`);
  return list[0];
};

const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64');
const PDF = Buffer.from('%PDF-1.4\n% zz-teste\n%%EOF\n');
const DENIED = /42501|permission denied|row-level security|403|Unauthorized|not authorized/i;
const ids = {};

async function main() {
  // ----------------------------------------------------------------- login
  await check('login por e-mail e senha (cliente)', async () => {
    const { data, error } = await customer.auth.signInWithPassword({ email: CUSTOMER_EMAIL, password: PASSWORD });
    if (error) throw new Error(describeError(error));
    ids.customer = data.user.id;
    return `token ${data.session.access_token.split('.')[0].length > 0 ? 'emitido' : '?'}`;
  });
  await check('login por e-mail e senha (admin)', async () => {
    const { data, error } = await admin.auth.signInWithPassword({ email: ADMIN_EMAIL, password: PASSWORD });
    if (error) throw new Error(describeError(error));
    ids.admin = data.user.id;
  });
  if (!ids.customer || !ids.admin) return;
  await check('preparação: remove sobras de execuções anteriores', async () => {
    const season = (await rows(admin.from('seasons').select('id').eq('slug', 'zz-teste-temporada')))[0];
    if (season) {
      await rows(admin.from('memberships').update({ status: 'revoked', revoked_at: new Date().toISOString(), revoke_reason: 'zz-teste' }).eq('season_id', season.id).select());
      await rows(admin.from('seasons').update({ status: 'archived' }).eq('id', season.id).select());
    }
    await removeTestRows();
  });


  // ----------------------------------------------------------------- visitante
  await check('visitante: vê as 6 coleções visíveis', async () => equal((await rows(anon.from('collections').select('slug'))).length, 6, 'coleções'));
  await check('visitante: nenhuma receita antes da publicação', async () => equal((await rows(anon.from('recipes').select('id'))).length, 0, 'receitas'));
  await check('visitante: temporada em rascunho não aparece', async () => equal((await rows(anon.from('seasons').select('id'))).length, 0, 'temporadas'));
  await check('visitante: desafios ativos visíveis', async () => `${(await rows(anon.from('challenges').select('id'))).length} desafios`);
  await check('visitante: ingredientes das receitas recusados', () => denied(anon.from('recipe_ingredients').select('id'), DENIED));
  await check('visitante: etapas recusadas', () => denied(anon.from('recipe_steps').select('id'), DENIED));
  await check('visitante: documentos de origem recusados', () => denied(anon.from('source_documents').select('id'), DENIED));
  await check('visitante: perfis recusados', () => denied(anon.from('profiles').select('id'), DENIED));
  await check('visitante: pedidos recusados', () => denied(anon.from('orders').select('id'), DENIED));
  await check('visitante: não grava em coleções', () => denied(anon.from('collections').insert({ slug: 'zz-teste-anon', name: 'x' }), DENIED));
  await check('visitante: my_access = sem login', async () => {
    const access = await rows(anon.rpc('my_access'));
    equal([access.authenticated, access.is_admin, access.has_access], [false, false, false], 'my_access');
  });
  await check('visitante: catalog_stats só com contagens', async () => {
    const stats = await rows(anon.rpc('catalog_stats'));
    equal(stats.length, 6, 'coleções');
    equal(stats.reduce((sum, s) => sum + s.published_recipes, 0), 0, 'publicadas');
    return `${stats.reduce((sum, s) => sum + s.in_preparation, 0)} itens em preparação`;
  });
  await check('visitante: admin_usage_stats recusada', () => denied(anon.rpc('admin_usage_stats'), DENIED));
  await check('visitante: process_payment_event recusada', () =>
    denied(anon.rpc('process_payment_event', { p_order_id: '00000000-0000-4000-8000-000000000000', p_provider_payment_id: 'x', p_status: 'approved', p_status_detail: null, p_amount_cents: 1, p_currency: 'BRL' }), DENIED));
  await check('visitante: write_audit_log recusada', () =>
    denied(anon.rpc('write_audit_log', { p_action: 'x', p_entity: 'x', p_entity_id: 'x', p_summary: 'x', p_old: null, p_new: null }), DENIED));
  await check('visitante: não envia arquivo para recipe-images', () => denied(anon.storage.from('recipe-images').upload('zz-teste/anon.png', PNG, { contentType: 'image/png' })));
  await check('visitante: não lista PDFs originais', async () => equal((await rows(anon.storage.from('source-documents').list('zz-teste'))).length, 0, 'arquivos'));

  // ----------------------------------------------------------------- cliente sem acesso
  await check('cliente: perfil criado pelo gatilho de cadastro', async () => {
    const profile = one(await rows(customer.from('profiles').select('*')), 'perfis visíveis');
    equal([profile.id, profile.role], [ids.customer, 'customer'], 'perfil');
    return profile.full_name;
  });
  await check('cliente: atualiza o próprio nome', async () => one(await rows(customer.from('profiles').update({ full_name: 'Teste Cliente (editado)' }).eq('id', ids.customer).select()), 'perfil').full_name);
  await check('cliente: NÃO consegue virar admin (coluna role)', () => denied(customer.from('profiles').update({ role: 'admin' }).eq('id', ids.customer).select(), DENIED));
  await check('cliente: admin_set_role recusada', () => denied(customer.rpc('admin_set_role', { p_user: ids.customer, p_role: 'admin' }), /FORBIDDEN|42501/));
  await check('cliente: my_access sem acesso', async () => {
    const access = await rows(customer.rpc('my_access'));
    equal([access.authenticated, access.is_admin, access.has_access], [true, false, false], 'my_access');
  });
  await check('cliente sem acesso: catálogo premium vazio', async () => {
    for (const table of ['recipes', 'recipe_ingredients', 'recipe_steps', 'recipe_step_timers', 'recipe_notes', 'ingredients']) {
      equal((await rows(customer.from(table).select('id'))).length, 0, table);
    }
  });
  await check('cliente sem acesso: não cria planejamento', () => denied(customer.from('meal_plans').insert({ title: 'zz-teste' }).select(), DENIED));
  await check('cliente: não cria pedido', () => denied(customer.from('orders').insert({ user_id: ids.customer, season_id: ids.customer, amount_cents: 1 }), DENIED));
  await check('cliente: não concede acesso a si mesmo', () => denied(customer.from('memberships').insert({ user_id: ids.customer, season_id: ids.customer, source: 'courtesy' }), DENIED));
  await check('cliente: não lê auditoria', async () => equal((await rows(customer.from('admin_audit_logs').select('id'))).length, 0, 'auditoria'));
  await check('cliente: não lê documentos de origem', async () => equal((await rows(customer.from('source_documents').select('id'))).length, 0, 'documentos'));
  await check('cliente: refresh_my_challenges', async () => `${(await rows(customer.rpc('refresh_my_challenges'))).length} desafios acompanhados`);

  // ----------------------------------------------------------------- administração
  await check('admin: my_access', async () => {
    const access = await rows(admin.rpc('my_access'));
    equal([access.is_admin, access.has_access], [true, true], 'my_access');
  });
  await check('admin: enxerga todo o catálogo em revisão', async () => {
    const [recipes, documents, flags, profiles] = await Promise.all([
      rows(admin.from('recipes').select('id')), rows(admin.from('source_documents').select('id')),
      rows(admin.from('review_flags').select('id')), rows(admin.from('profiles').select('id')),
    ]);
    if (profiles.length < 2) throw new Error('admin deveria ver todos os perfis');
    return `${recipes.length} receitas · ${documents.length} documentos · ${flags.length} pontos de revisão`;
  });
  await check('admin: admin_usage_stats', async () => `${(await rows(admin.rpc('admin_usage_stats'))).users} usuários`);
  await check('admin: cria coleção, documento e ficha de teste', async () => {
    ids.collection = one(await rows(admin.from('collections').insert({ slug: 'zz-teste-colecao', name: 'ZZ Teste (remover)', is_visible: false, position: 999 }).select()), 'coleção').id;
    ids.document = one(await rows(admin.from('source_documents').insert({ slug: 'zz-teste-doc', collection_id: ids.collection, title: 'ZZ Teste (remover)', commercial_permission: 'confirmed', permission_notes: 'teste automatizado' }).select()), 'documento').id;
    ids.recipe = one(await rows(admin.from('recipes').insert({ slug: 'zz-teste-receita', collection_id: ids.collection, source_document_id: ids.document, title: 'ZZ Receita de teste (remover)', content_state: 'structured', status: 'draft' }).select()), 'receita').id;
    ids.component = one(await rows(admin.from('recipe_components').insert({ recipe_id: ids.recipe, role: 'outro', title: 'Parte de teste', position: 1 }).select()), 'parte').id;
    ids.ingredient = one(await rows(admin.from('ingredients').insert({ slug: 'zz-teste-ingrediente', name: 'ZZ ingrediente de teste' }).select()), 'ingrediente').id;
    await rows(admin.from('recipe_ingredients').insert({ recipe_id: ids.recipe, component_id: ids.component, ingredient_id: ids.ingredient, position: 1, quantity: 1, unit: 'un', display_name: 'ingrediente de teste' }).select());
    ids.step = one(await rows(admin.from('recipe_steps').insert({ recipe_id: ids.recipe, component_id: ids.component, position: 1, instruction: 'Etapa de teste.' }).select()), 'etapa').id;
    const timer = one(await rows(admin.from('recipe_step_timers').insert({ step_id: ids.step, label: 'Timer de teste', duration_seconds: 60, kind: 'other' }).select()), 'timer');
    equal(timer.recipe_id, ids.recipe, 'recipe_id preenchido pelo gatilho');
  });
  await check('admin: publicar sem aprovar é recusado', () => denied(admin.from('recipes').update({ status: 'published' }).eq('id', ids.recipe).select(), /APPROVAL_REQUIRED/));
  await check('admin: aprova e publica a ficha de teste', async () => {
    const approved = one(await rows(admin.from('recipes').update({ status: 'approved' }).eq('id', ids.recipe).select()), 'aprovação');
    equal(approved.reviewed_by, ids.admin, 'reviewed_by');
    const published = one(await rows(admin.from('recipes').update({ status: 'published' }).eq('id', ids.recipe).select()), 'publicação');
    if (!published.published_at) throw new Error('published_at vazio');
  });
  await check('admin: auditoria registrou a publicação com autoria', async () => {
    const logs = await rows(admin.from('admin_audit_logs').select('action, actor_email').eq('entity_id', ids.recipe).eq('action', 'recipes.status_changed'));
    equal(logs.length, 2, 'mudanças de situação');
    equal(logs[0].actor_email, ADMIN_EMAIL, 'autor');
  });
  await check('admin: abre temporada de teste e concede cortesia', async () => {
    const day = 24 * 60 * 60 * 1000;
    const window = { name: 'ZZ Temporada de teste', status: 'active', access_starts_at: new Date(Date.now() - day).toISOString(), access_ends_at: new Date(Date.now() + day).toISOString() };
    const season = (await rows(admin.from('seasons').select('id').eq('slug', 'zz-teste-temporada')))[0];
    ids.season = one(await rows(season ? admin.from('seasons').update(window).eq('id', season.id).select() : admin.from('seasons').insert({ slug: 'zz-teste-temporada', ...window }).select()), 'temporada').id;
    const membership = (await rows(admin.from('memberships').select('id').eq('user_id', ids.customer).eq('season_id', ids.season)))[0];
    one(await rows(membership
      ? admin.from('memberships').update({ status: 'active', source: 'courtesy', revoked_at: null, revoke_reason: null }).eq('id', membership.id).select()
      : admin.from('memberships').insert({ user_id: ids.customer, season_id: ids.season, source: 'courtesy', granted_by: ids.admin }).select()), 'acesso');
  });
  await check('admin: guarda e substitui PDF no bucket privado', async () => {
    for (const attempt of [1, 2]) {
      // o painel envia com upsert: a segunda passada substitui o arquivo
      const { error } = await admin.storage.from('source-documents').upload('zz-teste/original.pdf', PDF, { contentType: 'application/pdf', upsert: true });
      if (error) throw new Error(`envio ${attempt}: ${describeError(error)}`);
      ids.pdf = true;
    }
    equal((await rows(admin.storage.from('source-documents').list('zz-teste'))).length, 1, 'arquivos no bucket');
  });
  await check('admin: bucket privado recusa arquivo que não é PDF', () => denied(admin.storage.from('source-documents').upload('zz-teste/foto.png', PNG, { contentType: 'image/png' })));
  await check('admin: publica capa em recipe-images (leitura pública)', async () => {
    const { error } = await admin.storage.from('recipe-images').upload('zz-teste/capa.png', PNG, { contentType: 'image/png' });
    if (error) throw new Error(describeError(error));
    ids.cover = true;
    const response = await fetch(admin.storage.from('recipe-images').getPublicUrl('zz-teste/capa.png').data.publicUrl);
    equal(response.status, 200, 'URL pública');
  });
  await check('admin: substitui e remove a capa', async () => {
    const { error } = await admin.storage.from('recipe-images').upload('zz-teste/capa.png', PNG, { contentType: 'image/png', upsert: true });
    if (error) throw new Error(`substituição: ${describeError(error)}`);
    await rows(admin.storage.from('recipe-images').remove(['zz-teste/capa.png']));
    equal((await rows(admin.storage.from('recipe-images').list('zz-teste'))).length, 0, 'capas restantes');
    ids.cover = false;
  });

  // ----------------------------------------------------------------- cliente com acesso
  await check('cliente com cortesia: my_access liberado', async () => {
    const access = await rows(customer.rpc('my_access'));
    equal([access.has_access, access.is_admin, access.source], [true, false, 'courtesy'], 'my_access');
    return access.season_name;
  });
  await check('cliente com acesso: lê somente a ficha publicada', async () => {
    equal((await rows(customer.from('recipes').select('slug'))).map((r) => r.slug), ['zz-teste-receita'], 'receitas');
    for (const table of ['recipe_components', 'recipe_ingredients', 'recipe_steps', 'recipe_step_timers']) {
      const list = await rows(customer.from(table).select('recipe_id'));
      equal([...new Set(list.map((r) => r.recipe_id))], [ids.recipe], table);
    }
    return 'fichas não publicadas continuam invisíveis';
  });
  await check('cliente: não baixa o PDF original', async () => {
    const { data, error } = await customer.storage.from('source-documents').download('zz-teste/original.pdf');
    if (!error && data) throw new Error('PDF original ficou acessível a um cliente');
    return 'recusado';
  });
  await check('cliente: favorita, planeja, lista e cozinha', async () => {
    await rows(customer.from('recipe_favorites').insert({ recipe_id: ids.recipe }).select());
    const plan = one(await rows(customer.from('meal_plans').insert({ title: 'zz-teste ceia', occasion: 'natal', guests: 4, event_date: '2026-12-24' }).select()), 'plano');
    equal(plan.user_id, ids.customer, 'dono do plano');
    ids.plan = plan.id;
    await rows(customer.from('plan_recipes').insert({ plan_id: ids.plan, recipe_id: ids.recipe, factor: 2 }).select());
    await rows(customer.from('plan_tasks').insert({ plan_id: ids.plan, title: 'zz-teste tarefa', kind: 'custom' }).select());
    ids.list = one(await rows(customer.from('shopping_lists').insert({ title: 'zz-teste lista' }).select()), 'lista').id;
    await rows(customer.from('shopping_items').insert({ list_id: ids.list, name: 'zz-teste item', quantity: 2, unit: 'un' }).select());
    ids.session = one(await rows(customer.from('cooking_sessions').insert({ recipe_id: ids.recipe, factor: 1 }).select()), 'sessão').id;
    one(await rows(customer.from('cooking_sessions').update({ status: 'finished', finished_at: new Date().toISOString() }).eq('id', ids.session).select()), 'sessão concluída');
  });
  await check('cliente: desafio "cozinhar uma receita" concluído no servidor', async () => {
    const progress = await rows(customer.rpc('refresh_my_challenges'));
    const done = progress.filter((p) => p.completed_at);
    if (!done.length) throw new Error('nenhum desafio concluído após terminar uma receita');
    return `${done.length} concluído(s), ${done.reduce((sum, p) => sum + p.points_awarded, 0)} pontos`;
  });
  await check('cliente: não altera o próprio progresso de desafios', () => denied(customer.from('user_challenges').update({ points_awarded: 9999 }).eq('user_id', ids.customer).select(), DENIED));
  await check('cliente: conversa com o Chef é gravada e não pode ser editada', async () => {
    ids.conversation = one(await rows(customer.from('ai_conversations').insert({ title: 'zz-teste' }).select()), 'conversa').id;
    one(await rows(customer.from('ai_messages').insert({ conversation_id: ids.conversation, role: 'user', content: 'zz-teste' }).select()), 'mensagem');
    return denied(customer.from('ai_messages').update({ content: 'x' }).eq('conversation_id', ids.conversation).select(), DENIED);
  });
  await check('cliente: envia foto de desafio só na própria pasta', async () => {
    const own = `${ids.customer}/zz-teste.png`;
    const { error } = await customer.storage.from('challenge-photos').upload(own, PNG, { contentType: 'image/png' });
    if (error) throw new Error(describeError(error));
    ids.photo = own;
    await denied(customer.storage.from('challenge-photos').upload(`${ids.admin}/zz-teste.png`, PNG, { contentType: 'image/png' }));
    const challenge = (await rows(customer.from('challenges').select('id').limit(1)))[0];
    ids.submission = one(await rows(customer.from('challenge_submissions').insert({ challenge_id: challenge.id, photo_path: own, note: 'zz-teste' }).select()), 'envio').id;
    await denied(customer.from('challenge_submissions').insert({ challenge_id: challenge.id, photo_path: `${ids.admin}/zz-teste.png` }).select(), DENIED);
    await denied(customer.from('challenge_submissions').insert({ challenge_id: challenge.id, user_id: ids.admin }).select(), DENIED);
    const { data: signed, error: signError } = await customer.storage.from('challenge-photos').createSignedUrl(own, 60);
    if (signError || !signed?.signedUrl) throw new Error('não gerou URL assinada da própria foto');
  });
  await check('isolamento: admin não lê planos, listas nem conversas de clientes', async () => {
    for (const table of ['meal_plans', 'shopping_lists', 'shopping_items', 'cooking_sessions', 'ai_conversations', 'ai_messages', 'recipe_favorites']) {
      equal((await rows(admin.from(table).select('id'))).length, 0, table);
    }
  });
  await check('admin: modera o envio de foto', async () => one(await rows(admin.from('challenge_submissions').update({ status: 'approved', reviewed_by: ids.admin, reviewed_at: new Date().toISOString() }).eq('id', ids.submission).select()), 'envio').status);
  if (KEEP) return;
  await check('admin: revoga a cortesia e o cliente perde o acesso', async () => {
    one(await rows(admin.from('memberships').update({ status: 'revoked', revoked_at: new Date().toISOString(), revoke_reason: 'zz-teste' }).eq('user_id', ids.customer).eq('season_id', ids.season).select()), 'revogação');
    equal((await rows(customer.rpc('my_access'))).has_access, false, 'acesso depois da revogação');
    equal((await rows(customer.from('recipe_steps').select('id'))).length, 0, 'etapas visíveis');
  });
}

/** Apaga, pela API, tudo o que o teste cria e as roles de teste conseguem apagar. */
async function removeTestRows() {
  if (ids.customer) {
    for (const table of ['challenge_submissions', 'cooking_sessions', 'shopping_lists', 'meal_plans', 'recipe_favorites']) {
      await rows(customer.from(table).delete().eq('user_id', ids.customer));
    }
    await rows(customer.from('profiles').update({ full_name: 'Teste Cliente' }).eq('id', ids.customer).select());
  }
  await rows(admin.from('recipes').delete().eq('slug', 'zz-teste-receita'));
  await rows(admin.from('ingredients').delete().eq('slug', 'zz-teste-ingrediente'));
  await rows(admin.from('source_documents').delete().eq('slug', 'zz-teste-doc'));
  await rows(admin.from('collections').delete().eq('slug', 'zz-teste-colecao'));
}

async function cleanup() {
  const quiet = async (promise) => {
    try {
      await promise;
    } catch {
      /* limpeza: melhor esforço */
    }
  };
  if (KEEP) console.log('SMOKE_KEEP=1: ficha, temporada e acesso de teste mantidos no banco (arquivos do Storage removidos).');
  if (ids.photo) await quiet(customer.storage.from('challenge-photos').remove([ids.photo]));
  if (ids.pdf) await quiet(admin.storage.from('source-documents').remove(['zz-teste/original.pdf']));
  if (ids.cover) await quiet(admin.storage.from('recipe-images').remove(['zz-teste/capa.png']));
  await check('limpeza: nenhum arquivo de teste ficou no Storage', async () => {
    const left = [
      ...(await rows(admin.storage.from('source-documents').list('zz-teste'))),
      ...(await rows(admin.storage.from('recipe-images').list('zz-teste'))),
      ...(ids.customer ? await rows(admin.storage.from('challenge-photos').list(ids.customer)) : []),
    ];
    equal(left.map((file) => file.name), [], 'arquivos restantes');
  });
  if (KEEP) return;
  await quiet(removeTestRows());
}

try {
  await main();
} finally {
  await cleanup();
}
console.log(`\n${passed} verificações OK · ${failures.length} falha(s)`);
if (failures.length) {
  console.log(failures.map((name) => `  ✗ ${name}`).join('\n'));
  process.exit(1);
}
