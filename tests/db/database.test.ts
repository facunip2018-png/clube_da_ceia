import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { TestDb, errorOf } from './harness';

/**
 * Testes de banco: executam as migrations e a carga reais em um PostgreSQL (PGlite)
 * e verificam as regras de segurança e de negócio como a API do Supabase as veria.
 */
let db: TestDb;
let admin: string;
let ana: string; // cliente com acesso
let bia: string; // cliente sem acesso
let seasonId: string;
let paveId: string;
let paveDocId: string;

beforeAll(async () => {
  db = await TestDb.create();
  admin = await db.createUser('admin@clube.test', { admin: true, fullName: 'Admin' });
  ana = await db.createUser('ana@clube.test', { fullName: 'Ana' });
  bia = await db.createUser('bia@clube.test');
  [{ id: seasonId }] = await db.sql<{ id: string }>(`select id from public.seasons limit 1`);
  [{ id: paveId, source_document_id: paveDocId }] = await db.sql<{ id: string; source_document_id: string }>(
    `select id, source_document_id from public.recipes where slug = 'pave-floresta-negra-com-creme-danete'`,
  );
}, 60_000);

afterAll(async () => {
  await db.close();
});

describe('estrutura e carga', () => {
  it('cria as 31 tabelas, todas com RLS ligado', async () => {
    const rows = await db.sql<{ tablename: string; rowsecurity: boolean }>(
      `select tablename, rowsecurity from pg_tables where schemaname = 'public'`,
    );
    expect(rows).toHaveLength(31);
    expect(rows.filter((r) => !r.rowsecurity)).toEqual([]);
  });

  it('carrega o catálogo sem inventar conteúdo: 62 itens, 26 com ficha estruturada', async () => {
    const [stats] = await db.sql<Record<string, number>>(`
      select count(*)::int as total,
             count(*) filter (where content_state = 'structured')::int as structured,
             count(*) filter (where status = 'published')::int as published,
             count(*) filter (where status = 'pending_permission')::int as blocked
      from public.recipes`);
    expect(stats).toEqual({ total: 62, structured: 26, published: 0, blocked: 10 });
    // receitas sem PDF não têm ingredientes nem etapas
    const [orphans] = await db.sql<{ n: number }>(`
      select count(*)::int as n from public.recipe_ingredients i
      join public.recipes r on r.id = i.recipe_id where r.content_state = 'catalogued'`);
    expect(orphans.n).toBe(0);
  });

  it('preserva as quantidades originais do Pavê Floresta Negra', async () => {
    const rows = await db.sql<{ display_name: string; quantity: string | null; unit: string | null; quantity_text: string | null; original_text: string }>(
      `select display_name, quantity, unit, quantity_text, original_text from public.recipe_ingredients where recipe_id = $1 order by component_id, position`,
      [paveId],
    );
    expect(rows).toHaveLength(12);
    const by = Object.fromEntries(rows.map((r) => [r.display_name, r]));
    expect(Number(by['leite condensado'].quantity)).toBe(600);
    expect(by['leite condensado'].unit).toBe('g');
    expect(by['leite condensado'].original_text).toBe('600g de leite condensado (1 lata e meia)');
    expect(Number(by['água'].quantity)).toBe(75);
    expect(by['granulé'].quantity).toBeNull();
    expect(by['granulé'].quantity_text).toBe('quantidade não informada');
    const timers = await db.sql<{ duration_seconds: number; is_minimum: boolean }>(
      `select duration_seconds, is_minimum from public.recipe_step_timers where recipe_id = $1 order by duration_seconds`,
      [paveId],
    );
    expect(timers).toEqual([
      { duration_seconds: 240, is_minimum: false },
      { duration_seconds: 21600, is_minimum: true },
    ]);
  });

  it('a carga é idempotente e não sobrescreve ajustes do administrador', async () => {
    await db.sql(`update public.collections set description = 'Editado no painel' where slug = 'paves'`);
    await db.sql(`update public.recipe_ingredients set quantity = 601 where recipe_id = $1 and display_name = 'leite condensado'`, [paveId]);
    await db.sql(`update public.seasons set price_cents = 4990 where id = $1`, [seasonId]);
    const before = await db.sql(`select (select count(*) from public.recipes) a, (select count(*) from public.recipe_steps) b, (select count(*) from public.review_flags) c, (select count(*) from public.recipe_step_ingredients) d`);
    await db.seed();
    await db.seed();
    const after = await db.sql(`select (select count(*) from public.recipes) a, (select count(*) from public.recipe_steps) b, (select count(*) from public.review_flags) c, (select count(*) from public.recipe_step_ingredients) d`);
    expect(after).toEqual(before);
    const [c] = await db.sql<{ description: string }>(`select description from public.collections where slug = 'paves'`);
    expect(c.description).toBe('Editado no painel');
    const [i] = await db.sql<{ quantity: string }>(`select quantity from public.recipe_ingredients where recipe_id = $1 and display_name = 'leite condensado'`, [paveId]);
    expect(Number(i.quantity)).toBe(601);
    const [s] = await db.sql<{ price_cents: number }>(`select price_cents from public.seasons where id = $1`, [seasonId]);
    expect(s.price_cents).toBe(4990);
    await db.sql(`update public.recipe_ingredients set quantity = 600 where recipe_id = $1 and display_name = 'leite condensado'`, [paveId]);
    await db.sql(`update public.seasons set price_cents = null where id = $1`, [seasonId]);
  });

  it('cria o perfil automaticamente no cadastro, como cliente', async () => {
    const [p] = await db.sql<{ role: string; full_name: string; email: string }>(`select role, full_name, email from public.profiles where id = $1`, [ana]);
    expect(p).toEqual({ role: 'customer', full_name: 'Ana', email: 'ana@clube.test' });
  });
});

describe('fluxo editorial e permissão comercial', () => {
  it('visitante não vê receitas enquanto nada está publicado, mas vê as coleções', async () => {
    await db.as('anon', null, async (q) => {
      expect(await q(`select id from public.recipes`)).toHaveLength(0);
      expect(await q(`select id from public.collections`)).toHaveLength(6);
      const stats = await q<{ in_preparation: number; published_recipes: number }>(`select * from public.catalog_stats()`);
      expect(stats).toHaveLength(6);
      expect(stats.reduce((n, s) => n + s.in_preparation, 0)).toBe(62);
      expect(stats.reduce((n, s) => n + s.published_recipes, 0)).toBe(0);
    });
  });

  it('cliente não consegue alterar status de receita', async () => {
    await db.as('authenticated', ana, async (q) => {
      const rows = await q(`update public.recipes set status = 'published' where id = $1 returning id`, [paveId]);
      expect(rows).toHaveLength(0); // RLS: nenhuma linha visível para atualizar
    });
  });

  it('não aprova com pontos de revisão em aberto', async () => {
    await db.as('authenticated', admin, async (q) => {
      const message = await errorOf(q(`update public.recipes set status = 'approved' where id = $1`, [paveId]));
      expect(message).toContain('FLAGS_PENDING');
    });
  });

  it('não aprova nem publica item sem ficha estruturada', async () => {
    await db.as('authenticated', admin, async (q) => {
      const message = await errorOf(q(`update public.recipes set status = 'approved' where slug = 'panetone-tradicional'`));
      expect(message).toContain('CONTENT_REQUIRED');
    });
  });

  it('após resolver os pontos, aprova; mas não publica sem permissão comercial confirmada', async () => {
    await db.as('authenticated', admin, async (q) => {
      await q(`update public.review_flags set resolved_at = now(), resolved_by = $2, resolution_note = 'Conferido com o PDF' where recipe_id = $1 and resolved_at is null`, [paveId, admin]);
      const skip = await errorOf(q(`update public.recipes set status = 'published' where id = $1`, [paveId]));
      expect(skip).toContain('APPROVAL_REQUIRED');
      await q(`update public.recipes set status = 'approved' where id = $1`, [paveId]);
      const message = await errorOf(q(`update public.recipes set status = 'published' where id = $1`, [paveId]));
      expect(message).toContain('PERMISSION_REQUIRED');
    });
    const [r] = await db.sql<{ status: string; reviewed_by: string }>(`select status, reviewed_by from public.recipes where id = $1`, [paveId]);
    expect(r).toEqual({ status: 'approved', reviewed_by: admin });
  });

  it('com a permissão confirmada, publica — e a vitrine pública passa a mostrar a receita', async () => {
    await db.as('authenticated', admin, async (q) => {
      await q(`update public.source_documents set commercial_permission = 'confirmed', permission_notes = 'Autorização por escrito da autora' where id = $1`, [paveDocId]);
      await q(`update public.recipes set status = 'published' where id = $1`, [paveId]);
    });
    const [doc] = await db.sql<{ permission_confirmed_by: string }>(`select permission_confirmed_by from public.source_documents where id = $1`, [paveDocId]);
    expect(doc.permission_confirmed_by).toBe(admin);
    await db.as('anon', null, async (q) => {
      const rows = await q<{ slug: string }>(`select slug from public.recipes`);
      expect(rows.map((r) => r.slug)).toEqual(['pave-floresta-negra-com-creme-danete']);
      const refs = await q<{ title: string; author: string }>(`select title, author from public.source_document_refs`);
      expect(refs).toEqual([{ title: 'Pavê Floresta Negra', author: 'Valéria Ribeiro' }]);
      const [stats] = await q<{ published_recipes: number }>(
        `select s.published_recipes from public.catalog_stats() s join public.collections c on c.id = s.collection_id where c.slug = 'paves'`,
      );
      expect(stats.published_recipes).toBe(1);
    });
  });

  it('registra as ações administrativas na auditoria', async () => {
    const logs = await db.sql<{ action: string; actor_id: string }>(`select action, actor_id from public.admin_audit_logs order by created_at`);
    const actions = logs.map((l) => l.action);
    expect(actions).toContain('review_flags.resolved');
    expect(actions).toContain('source_documents.permission_changed');
    expect(actions.filter((a) => a === 'recipes.status_changed')).toHaveLength(2);
    expect(logs.every((l) => l.actor_id === admin)).toBe(true);
    await db.as('authenticated', ana, async (q) => {
      expect(await q(`select id from public.admin_audit_logs`)).toHaveLength(0);
      expect(await errorOf(q(`insert into public.admin_audit_logs (action, entity) values ('x', 'y')`))).toMatch(/permission denied/i);
    });
  });
});

describe('conteúdo premium e acesso por temporada', () => {
  it('visitante vê a capa da receita publicada, mas não ingredientes nem etapas', async () => {
    await db.as('anon', null, async (q) => {
      expect(await errorOf(q(`select id from public.recipe_ingredients`))).toMatch(/permission denied/i);
      expect(await errorOf(q(`select id from public.recipe_steps`))).toMatch(/permission denied/i);
      expect(await errorOf(q(`select id from public.source_documents`))).toMatch(/permission denied/i);
    });
  });

  it('cliente sem acesso não lê ingredientes, etapas, dicas ou temporizadores', async () => {
    await db.as('authenticated', bia, async (q) => {
      for (const table of ['recipe_components', 'recipe_ingredients', 'recipe_steps', 'recipe_step_ingredients', 'recipe_step_timers', 'recipe_notes', 'ingredients']) {
        expect(await q(`select id from public.${table}`), table).toHaveLength(0);
      }
      expect(await q(`select id from public.source_documents`)).toHaveLength(0);
      expect(await q(`select id from public.review_flags`)).toHaveLength(0);
      const [access] = await q<{ my_access: { has_access: boolean; is_admin: boolean } }>(`select public.my_access()`);
      expect(access.my_access.has_access).toBe(false);
      expect(await errorOf(q(`insert into public.meal_plans (title) values ('Ceia')`))).toMatch(/row-level security/i);
    });
  });

  it('temporada em rascunho não libera acesso, mesmo com membership', async () => {
    await db.sql(`insert into public.memberships (user_id, season_id, source) values ($1, $2, 'courtesy')`, [ana, seasonId]);
    await db.as('authenticated', ana, async (q) => {
      expect(await q(`select id from public.recipe_ingredients`)).toHaveLength(0);
    });
  });

  it('com temporada ativa e membership, o cliente lê a ficha completa da receita publicada', async () => {
    await db.sql(`update public.seasons set status = 'active', price_cents = 4990, access_starts_at = now() - interval '1 day', access_ends_at = now() + interval '30 days' where id = $1`, [seasonId]);
    await db.as('authenticated', ana, async (q) => {
      expect(await q(`select id from public.recipe_ingredients`)).toHaveLength(12);
      expect(await q(`select id from public.recipe_steps`)).toHaveLength(16);
      expect(await q(`select id from public.recipe_step_timers`)).toHaveLength(2);
      const [access] = await q<{ my_access: { has_access: boolean; season_name: string } }>(`select public.my_access()`);
      expect(access.my_access.has_access).toBe(true);
      expect(access.my_access.season_name).toBe('Natal & Ano-Novo 2026');
      // rascunhos continuam invisíveis
      expect(await q(`select id from public.recipes`)).toHaveLength(1);
    });
    await db.as('authenticated', bia, async (q) => {
      expect(await q(`select id from public.recipe_ingredients`)).toHaveLength(0);
    });
  });

  it('acesso termina quando a janela da temporada acaba', async () => {
    await db.sql(`update public.seasons set access_starts_at = now() - interval '40 days', access_ends_at = now() - interval '1 day' where id = $1`, [seasonId]);
    await db.as('authenticated', ana, async (q) => {
      expect(await q(`select id from public.recipe_steps`)).toHaveLength(0);
    });
    await db.sql(`update public.seasons set access_starts_at = now() - interval '1 day', access_ends_at = now() + interval '30 days' where id = $1`, [seasonId]);
  });

  it('se a permissão comercial for retirada, a receita sai do ar', async () => {
    await db.as('authenticated', admin, async (q) => {
      await q(`update public.source_documents set commercial_permission = 'restricted' where id = $1`, [paveDocId]);
    });
    const [r] = await db.sql<{ status: string }>(`select status from public.recipes where id = $1`, [paveId]);
    expect(r.status).toBe('pending_permission');
    await db.as('authenticated', ana, async (q) => {
      expect(await q(`select id from public.recipes`)).toHaveLength(0);
      expect(await q(`select id from public.recipe_ingredients`)).toHaveLength(0);
    });
    // restaura: confirmar de novo devolve para revisão; o admin aprova e publica outra vez
    await db.as('authenticated', admin, async (q) => {
      await q(`update public.source_documents set commercial_permission = 'confirmed' where id = $1`, [paveDocId]);
      const [row] = await q<{ status: string }>(`select status from public.recipes where id = $1`, [paveId]);
      expect(row.status).toBe('review');
      await q(`update public.recipes set status = 'approved' where id = $1`, [paveId]);
      await q(`update public.recipes set status = 'published' where id = $1`, [paveId]);
    });
  });
});

describe('dados de cada pessoa', () => {
  it('cada cliente enxerga apenas os próprios planos, listas, favoritos e sessões', async () => {
    let planId = '';
    await db.as('authenticated', ana, async (q) => {
      [{ id: planId }] = await q<{ id: string }>(`insert into public.meal_plans (title, occasion, event_date, guests) values ('Ceia da Ana', 'natal', '2026-12-24', 10) returning id`);
      await q(`insert into public.plan_recipes (plan_id, recipe_id, factor) values ($1, $2, 2)`, [planId, paveId]);
      await q(`insert into public.plan_tasks (plan_id, title, ref_key) values ($1, 'Comprar ingredientes', 'default:compras')`, [planId]);
      await q(`insert into public.recipe_favorites (recipe_id) values ($1)`, [paveId]);
      const [list] = await q<{ id: string }>(`insert into public.shopping_lists (title) values ('Lista') returning id`);
      await q(`insert into public.shopping_items (list_id, name, quantity, unit) values ($1, 'Leite condensado', 1200, 'g')`, [list.id]);
      await q(`insert into public.cooking_sessions (recipe_id) values ($1)`, [paveId]);
    });
    await db.as('authenticated', bia, async (q) => {
      for (const table of ['meal_plans', 'plan_recipes', 'plan_tasks', 'recipe_favorites', 'shopping_lists', 'shopping_items', 'cooking_sessions']) {
        expect(await q(`select id from public.${table}`), table).toHaveLength(0);
      }
      // não consegue gravar no plano de outra pessoa nem se passar por ela
      expect(await errorOf(q(`insert into public.plan_tasks (plan_id, title) values ($1, 'Intrusa')`, [planId]))).toMatch(/row-level security/i);
      expect(await errorOf(q(`insert into public.recipe_favorites (user_id, recipe_id) values ($1, $2)`, [ana, paveId]))).toMatch(/row-level security/i);
      expect(await q(`update public.meal_plans set title = 'hack' where id = $1 returning id`, [planId])).toHaveLength(0);
      expect(await q(`delete from public.meal_plans where id = $1 returning id`, [planId])).toHaveLength(0);
    });
    await db.as('authenticated', admin, async (q) => {
      // nem a administração lê os planos particulares pelo app
      expect(await q(`select id from public.meal_plans`)).toHaveLength(0);
    });
    await db.as('anon', null, async (q) => {
      expect(await errorOf(q(`select id from public.meal_plans`))).toMatch(/permission denied/i);
    });
  });

  it('o cliente não consegue se promover a administrador', async () => {
    await db.as('authenticated', ana, async (q) => {
      expect(await errorOf(q(`update public.profiles set role = 'admin' where id = $1`, [ana]))).toMatch(/permission denied/i);
      expect(await errorOf(q(`select public.admin_set_role($1, 'admin')`, [ana]))).toContain('FORBIDDEN');
      expect(await errorOf(q(`select public.admin_usage_stats()`))).toContain('FORBIDDEN');
      await q(`update public.profiles set full_name = 'Ana Maria' where id = $1`, [ana]);
      expect(await q(`select id from public.profiles`)).toHaveLength(1);
    });
    const [p] = await db.sql<{ role: string; full_name: string }>(`select role, full_name from public.profiles where id = $1`, [ana]);
    expect(p).toEqual({ role: 'customer', full_name: 'Ana Maria' });
  });

  it('administrador promove outra pessoa pela função protegida, com registro em auditoria', async () => {
    await db.as('authenticated', admin, async (q) => {
      await q(`select public.admin_set_role($1, 'admin')`, [bia]);
      expect(await errorOf(q(`select public.admin_set_role($1, 'customer')`, [admin]))).toContain('SELF_DEMOTION');
      await q(`select public.admin_set_role($1, 'customer')`, [bia]);
      const [stats] = await q<{ admin_usage_stats: { users: number; plans: number } }>(`select public.admin_usage_stats()`);
      expect(stats.admin_usage_stats.users).toBe(3);
      expect(stats.admin_usage_stats.plans).toBe(1);
    });
    const logs = await db.sql(`select 1 from public.admin_audit_logs where action = 'profiles.role_changed'`);
    expect(logs).toHaveLength(2);
  });
});

describe('desafios', () => {
  it('o progresso é calculado pelo servidor e não pode ser gravado pelo cliente', async () => {
    const [challenge] = await db.sql<{ id: string }>(`select id from public.challenges where slug = 'sobremesa-especial'`);
    await db.as('authenticated', ana, async (q) => {
      expect(await errorOf(q(`insert into public.user_challenges (challenge_id, progress, target, completed_at, points_awarded) values ($1, 1, 1, now(), 999)`, [challenge.id]))).toMatch(/permission denied/i);
      let rows = await q<{ challenge_id: string; completed_at: string | null; points_awarded: number }>(`select * from public.refresh_my_challenges()`);
      expect(rows).toHaveLength(9);
      expect(rows.find((r) => r.challenge_id === challenge.id)?.completed_at).toBeNull();

      await q(`update public.cooking_sessions set status = 'finished', finished_at = now() where recipe_id = $1`, [paveId]);
      rows = await q(`select * from public.refresh_my_challenges()`);
      const done = rows.find((r) => r.challenge_id === challenge.id);
      expect(done?.completed_at).not.toBeNull();
      expect(done?.points_awarded).toBe(20);
    });
    // "Organize sua ceia" já estava concluído (plano com data e receita)
    const [plan] = await db.sql<{ completed_at: string | null }>(
      `select uc.completed_at from public.user_challenges uc join public.challenges c on c.id = uc.challenge_id where uc.user_id = $1 and c.slug = 'organize-sua-ceia'`,
      [ana],
    );
    expect(plan.completed_at).not.toBeNull();
  });

  it('conquista concluída não é perdida se o registro de origem for apagado', async () => {
    await db.as('authenticated', ana, async (q) => {
      await q(`delete from public.cooking_sessions`);
      const rows = await q<{ completed_at: string | null; points_awarded: number }>(
        `select r.* from public.refresh_my_challenges() r join public.challenges c on c.id = r.challenge_id where c.slug = 'sobremesa-especial'`,
      );
      expect(rows[0].completed_at).not.toBeNull();
      expect(rows[0].points_awarded).toBe(20);
    });
  });

  it('envio de foto fica restrito à pasta da própria pessoa', async () => {
    const [challenge] = await db.sql<{ id: string }>(`select id from public.challenges where slug = 'sobremesa-especial'`);
    await db.as('authenticated', ana, async (q) => {
      await q(`insert into public.challenge_submissions (challenge_id, photo_path, note) values ($1, $2, 'Ficou lindo')`, [challenge.id, `${ana}/pave.jpg`]);
      expect(await errorOf(q(`insert into public.challenge_submissions (challenge_id, photo_path) values ($1, $2)`, [challenge.id, `${bia}/x.jpg`]))).toMatch(/row-level security/i);
      // não consegue se autoaprovar
      expect(await q(`update public.challenge_submissions set status = 'approved' returning id`)).toHaveLength(0);
    });
    await db.as('authenticated', bia, async (q) => {
      expect(await q(`select id from public.challenge_submissions`)).toHaveLength(0);
    });
  });
});

describe('chef ia', () => {
  it('guarda o histórico por pessoa e não permite apagar mensagens (base do limite de uso)', async () => {
    await db.as('authenticated', ana, async (q) => {
      const [c] = await q<{ id: string }>(`insert into public.ai_conversations (title) values ('Dúvidas do pavê') returning id`);
      await q(`insert into public.ai_messages (conversation_id, role, content) values ($1, 'user', 'Posso congelar?')`, [c.id]);
      expect(await errorOf(q(`delete from public.ai_messages`))).toMatch(/permission denied/i);
      expect(await errorOf(q(`delete from public.ai_conversations`))).toMatch(/permission denied/i);
      expect(await errorOf(q(`update public.ai_messages set content = 'x'`))).toMatch(/permission denied/i);
    });
    await db.as('authenticated', bia, async (q) => {
      expect(await q(`select id from public.ai_messages`)).toHaveLength(0);
      // sem acesso válido não inicia conversa
      expect(await errorOf(q(`insert into public.ai_conversations (title) values ('x')`))).toMatch(/row-level security/i);
    });
  });
});

describe('pagamentos', () => {
  let orderId = '';
  const pay = (status: string, amount = 4990, paymentId = 'MP-1001', currency = 'BRL') =>
    db.as('service_role', null, async (q) => {
      const [row] = await q<{ result: { result: string; order_status: string; membership: string } }>(
        `select public.process_payment_event($1, $2, $3, 'detail', $4, $5, '{}'::jsonb) as result`,
        [orderId, paymentId, status, amount, currency],
      );
      return row.result;
    });
  const membership = async () =>
    (await db.sql<{ status: string; source: string }>(`select status, source from public.memberships where user_id = $1 and season_id = $2`, [bia, seasonId]))[0];

  it('o navegador não cria pedidos, não concede acesso e não processa pagamentos', async () => {
    await db.as('authenticated', bia, async (q) => {
      expect(await errorOf(q(`insert into public.orders (user_id, season_id, amount_cents) values ($1, $2, 1)`, [bia, seasonId]))).toMatch(/permission denied/i);
      expect(await errorOf(q(`insert into public.memberships (user_id, season_id, source) values ($1, $2, 'courtesy')`, [bia, seasonId]))).toMatch(/row-level security/i);
      expect(await errorOf(q(`select public.process_payment_event($1, 'x', 'approved', '', 1, 'BRL')`, [seasonId]))).toMatch(/permission denied/i);
      expect(await q(`select id from public.payment_transactions`)).toHaveLength(0);
    });
  });

  it('pagamento pendente não libera acesso', async () => {
    await db.as('service_role', null, async (q) => {
      [{ id: orderId }] = await q<{ id: string }>(`insert into public.orders (user_id, season_id, amount_cents, currency) values ($1, $2, 4990, 'BRL') returning id`, [bia, seasonId]);
    });
    expect((await pay('pending')).membership).toBe('unchanged');
    expect(await membership()).toBeUndefined();
  });

  it('valor divergente não libera acesso e marca o pedido para revisão', async () => {
    const result = await pay('approved', 100, 'MP-0999');
    expect(result).toMatchObject({ result: 'amount_mismatch', order_status: 'review_required' });
    expect(await membership()).toBeUndefined();
    expect((await pay('approved', 4990, 'MP-0998', 'USD')).result).toBe('amount_mismatch');
  });

  it('pagamento aprovado libera o acesso uma única vez, mesmo com webhooks repetidos', async () => {
    expect(await pay('approved')).toEqual({ result: 'applied', order_status: 'approved', membership: 'granted' });
    expect(await pay('approved')).toEqual({ result: 'applied', order_status: 'approved', membership: 'unchanged' });
    expect(await pay('approved')).toMatchObject({ membership: 'unchanged' });
    expect(await membership()).toEqual({ status: 'active', source: 'purchase' });
    const tx = await db.sql<{ seen_count: number }>(`select seen_count from public.payment_transactions where provider_payment_id = 'MP-1001' and status = 'approved'`);
    expect(tx).toEqual([{ seen_count: 3 }]);
    const [{ n }] = await db.sql<{ n: number }>(`select count(*)::int as n from public.memberships where user_id = $1`, [bia]);
    expect(n).toBe(1);
    await db.as('authenticated', bia, async (q) => {
      expect(await q(`select id from public.recipe_ingredients`)).toHaveLength(12);
      expect(await q(`select id from public.orders`)).toHaveLength(1);
    });
  });

  it('tentativa cancelada de outro pagamento não derruba o acesso já aprovado', async () => {
    expect(await pay('cancelled', 4990, 'MP-0777')).toMatchObject({ order_status: 'approved', membership: 'unchanged' });
    expect((await membership()).status).toBe('active');
  });

  it('disputa mantém o acesso; estorno revoga; reprocessar o estorno não muda nada', async () => {
    expect(await pay('in_mediation')).toMatchObject({ order_status: 'in_mediation', membership: 'unchanged' });
    expect((await membership()).status).toBe('active');
    expect(await pay('refunded')).toMatchObject({ order_status: 'refunded', membership: 'revoked' });
    expect(await pay('refunded')).toMatchObject({ order_status: 'refunded', membership: 'unchanged' });
    expect((await membership()).status).toBe('revoked');
    await db.as('authenticated', bia, async (q) => {
      expect(await q(`select id from public.recipe_ingredients`)).toHaveLength(0);
    });
  });

  it('bloqueio manual do administrador não é desfeito por evento de pagamento', async () => {
    await db.as('authenticated', admin, async (q) => {
      await q(`update public.memberships set admin_locked = true, revoke_reason = 'bloqueio manual' where user_id = $1`, [bia]);
    });
    expect(await pay('approved')).toMatchObject({ membership: 'locked_by_admin' });
    expect((await membership()).status).toBe('revoked');
  });

  it('pedido inexistente é ignorado com resposta controlada', async () => {
    const result = await db.as('service_role', null, async (q) => {
      const [row] = await q<{ r: { result: string } }>(`select public.process_payment_event(gen_random_uuid(), 'MP-1', 'approved', '', 1, 'BRL') as r`);
      return row.r;
    });
    expect(result).toEqual({ result: 'order_not_found' });
  });
});

describe('storage', () => {
  it('PDFs originais ficam em bucket privado, acessível apenas a administradores', async () => {
    const buckets = await db.sql<{ id: string; public: boolean }>(`select id, public from storage.buckets order by id`);
    expect(buckets).toEqual([
      { id: 'challenge-photos', public: false },
      { id: 'recipe-images', public: true },
      { id: 'source-documents', public: false },
    ]);
    await db.as('authenticated', admin, async (q) => {
      await q(`insert into storage.objects (bucket_id, name) values ('source-documents', 'paves/pave-floresta-negra.pdf')`);
      expect(await q(`select id from storage.objects where bucket_id = 'source-documents'`)).toHaveLength(1);
    });
    await db.as('authenticated', ana, async (q) => {
      expect(await q(`select id from storage.objects where bucket_id = 'source-documents'`)).toHaveLength(0);
      expect(await errorOf(q(`insert into storage.objects (bucket_id, name) values ('source-documents', 'x.pdf')`))).toMatch(/row-level security/i);
      // fotos: só na própria pasta
      await q(`insert into storage.objects (bucket_id, name) values ('challenge-photos', $1)`, [`${ana}/pave.jpg`]);
      expect(await errorOf(q(`insert into storage.objects (bucket_id, name) values ('challenge-photos', $1)`, [`${bia}/pave.jpg`]))).toMatch(/row-level security/i);
      expect(await errorOf(q(`insert into storage.objects (bucket_id, name) values ('recipe-images', 'capa.jpg')`))).toMatch(/row-level security/i);
    });
    await db.as('authenticated', bia, async (q) => {
      expect(await q(`select id from storage.objects`)).toHaveLength(0);
    });
  });
});

describe('instalação pelo arquivo único', () => {
  it('setup_completo.sql produz o mesmo banco que migrations + seed', async () => {
    const single = await TestDb.fromSetupFile();
    try {
      const count = async (target: TestDb, table: string) => (await target.sql<{ n: number }>(`select count(*)::int as n from public.${table}`))[0].n;
      for (const table of ['seasons', 'collections', 'source_documents', 'recipes', 'recipe_components', 'recipe_ingredients', 'recipe_steps', 'recipe_step_timers', 'review_flags', 'challenges', 'recipe_compatibilities']) {
        expect(await count(single, table), table).toBeGreaterThan(0);
      }
      expect(await count(single, 'recipes')).toBe(62);
      expect(await count(single, 'recipe_steps')).toBe(449);
      const [{ n }] = await single.sql<{ n: number }>(`select count(*)::int as n from pg_tables where schemaname = 'public' and rowsecurity`);
      expect(n).toBe(31);
      const [{ policies }] = await single.sql<{ policies: number }>(`select count(*)::int as policies from pg_policies where schemaname in ('public', 'storage')`);
      const [{ expected }] = await db.sql<{ expected: number }>(`select count(*)::int as expected from pg_policies where schemaname in ('public', 'storage')`);
      expect(policies).toBe(expected);
    } finally {
      await single.close();
    }
  }, 60_000);
});
