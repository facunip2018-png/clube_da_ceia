-- =====================================================================
-- Clube da Ceia Perfeita — 03. Segurança (RLS + permissões)
-- Princípios:
--   • visitante vê somente a vitrine: coleções visíveis e receitas publicadas (capa, título, tempos);
--   • ingredientes, etapas, dicas e temporizadores exigem acesso válido à temporada;
--   • cada pessoa enxerga apenas os próprios planos, listas, favoritos, sessões e conversas;
--   • pedidos, pagamentos e acessos só são gravados pelo servidor;
--   • administração é validada no banco (profiles.role), nunca no navegador.
-- =====================================================================

-- Começa do zero: nenhuma permissão implícita para as roles da API.
revoke all on all tables in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;

grant usage on schema public to anon, authenticated, service_role;
grant all on all tables in schema public to service_role;
grant execute on all functions in schema public to service_role;

-- Funções que as policies e o app utilizam.
grant execute on function public.request_role() to anon, authenticated;
grant execute on function public.is_admin() to anon, authenticated;
grant execute on function public.has_active_access() to anon, authenticated;
grant execute on function public.my_access() to anon, authenticated;
grant execute on function public.catalog_stats() to anon, authenticated;
grant execute on function public.refresh_my_challenges() to authenticated;
grant execute on function public.admin_set_role(uuid, text) to authenticated;
grant execute on function public.admin_usage_stats() to authenticated;
-- process_payment_event e write_audit_log: somente service_role (servidor).

-- RLS ligado em todas as tabelas do schema público.
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t.tablename);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- VITRINE (leitura pública)
-- ---------------------------------------------------------------------
grant select on public.seasons, public.collections, public.recipes, public.recipe_tags, public.challenges to anon, authenticated;

create policy "temporadas ativas sao publicas" on public.seasons
  for select to anon, authenticated
  using (status = 'active' or (select public.is_admin()));

create policy "colecoes visiveis sao publicas" on public.collections
  for select to anon, authenticated
  using (is_visible or (select public.is_admin()));

create policy "receitas publicadas sao publicas" on public.recipes
  for select to anon, authenticated
  using (status = 'published' or (select public.is_admin()));

create policy "tags de receitas publicadas" on public.recipe_tags
  for select to anon, authenticated
  using (
    (select public.is_admin())
    or exists (select 1 from public.recipes r where r.id = recipe_id and r.status = 'published')
  );

create policy "desafios ativos sao publicos" on public.challenges
  for select to anon, authenticated
  using (is_active or (select public.is_admin()));

-- Referência da fonte (título e autoria) das receitas publicadas, sem expor
-- arquivo, caminho no Storage ou anotações internas do documento.
create view public.source_document_refs as
  select d.id, d.title, d.author, d.publisher, d.language
  from public.source_documents d
  where exists (
    select 1 from public.recipes r
    where r.source_document_id = d.id and r.status = 'published'
  );
comment on view public.source_document_refs is
  'Visão pública mínima dos documentos de origem (somente os que têm receita publicada).';
revoke all on public.source_document_refs from anon, authenticated;
grant select on public.source_document_refs to anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- CONTEÚDO PREMIUM (exige acesso válido à temporada)
-- ---------------------------------------------------------------------
grant select on
  public.recipe_components, public.recipe_ingredients, public.recipe_steps,
  public.recipe_step_ingredients, public.recipe_step_timers, public.recipe_notes,
  public.recipe_compatibilities, public.ingredients
to authenticated;

do $$
declare t text;
begin
  foreach t in array array[
    'recipe_components', 'recipe_ingredients', 'recipe_steps', 'recipe_step_ingredients',
    'recipe_step_timers', 'recipe_notes', 'recipe_compatibilities'
  ] loop
    execute format($f$
      create policy "conteudo premium para quem tem acesso" on public.%I
        for select to authenticated
        using (
          (select public.is_admin())
          or (
            (select public.has_active_access())
            and exists (select 1 from public.recipes r where r.id = recipe_id and r.status = 'published')
          )
        )
    $f$, t);
  end loop;
end $$;

create policy "ingredientes para quem tem acesso" on public.ingredients
  for select to authenticated
  using ((select public.has_active_access()));

-- ---------------------------------------------------------------------
-- ADMINISTRAÇÃO DO CONTEÚDO
-- ---------------------------------------------------------------------
grant select, insert, update, delete on
  public.seasons, public.collections, public.source_documents, public.recipes, public.recipe_components,
  public.ingredients, public.recipe_ingredients, public.recipe_steps, public.recipe_step_ingredients,
  public.recipe_step_timers, public.recipe_notes, public.recipe_tags, public.recipe_compatibilities,
  public.review_flags, public.challenges
to authenticated;

do $$
declare t text;
begin
  foreach t in array array[
    'seasons', 'collections', 'source_documents', 'recipes', 'recipe_components', 'ingredients',
    'recipe_ingredients', 'recipe_steps', 'recipe_step_ingredients', 'recipe_step_timers', 'recipe_notes',
    'recipe_tags', 'recipe_compatibilities', 'review_flags', 'challenges'
  ] loop
    execute format($f$
      create policy "administradores gerenciam" on public.%I
        for all to authenticated
        using ((select public.is_admin()))
        with check ((select public.is_admin()))
    $f$, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- PERFIL
-- ---------------------------------------------------------------------
grant select on public.profiles to authenticated;
-- A role NÃO está na lista: o próprio usuário não consegue alterá-la.
grant update (full_name, avatar_url, preferences) on public.profiles to authenticated;

create policy "perfil proprio ou administracao" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()));

create policy "atualiza o proprio perfil" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- ---------------------------------------------------------------------
-- DADOS DE CADA PESSOA
-- ---------------------------------------------------------------------
grant select, insert, delete on public.recipe_favorites to authenticated;
grant select, insert, update, delete on
  public.meal_plans, public.plan_recipes, public.plan_tasks, public.shopping_lists,
  public.shopping_items, public.cooking_sessions
to authenticated;

create policy "favoritos proprios" on public.recipe_favorites
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Planos, sessões de preparo: criar exige acesso válido; ler/editar/apagar os próprios é sempre permitido.
create policy "le os proprios planos" on public.meal_plans
  for select to authenticated using (user_id = (select auth.uid()));
create policy "cria planos com acesso valido" on public.meal_plans
  for insert to authenticated
  with check (user_id = (select auth.uid()) and (select public.has_active_access()));
create policy "edita os proprios planos" on public.meal_plans
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "apaga os proprios planos" on public.meal_plans
  for delete to authenticated using (user_id = (select auth.uid()));

create policy "itens dos proprios planos" on public.plan_recipes
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.meal_plans p where p.id = plan_id and p.user_id = (select auth.uid()))
  );

create policy "tarefas dos proprios planos" on public.plan_tasks
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.meal_plans p where p.id = plan_id and p.user_id = (select auth.uid()))
  );

create policy "listas proprias" on public.shopping_lists
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "itens das proprias listas" on public.shopping_items
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.shopping_lists l where l.id = list_id and l.user_id = (select auth.uid()))
  );

create policy "le as proprias sessoes" on public.cooking_sessions
  for select to authenticated using (user_id = (select auth.uid()));
create policy "inicia preparo com acesso valido" on public.cooking_sessions
  for insert to authenticated
  with check (user_id = (select auth.uid()) and (select public.has_active_access()));
create policy "atualiza as proprias sessoes" on public.cooking_sessions
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "apaga as proprias sessoes" on public.cooking_sessions
  for delete to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------
-- DESAFIOS
-- ---------------------------------------------------------------------
-- Progresso: somente leitura. Quem grava é refresh_my_challenges().
grant select on public.user_challenges to authenticated;
create policy "le o proprio progresso" on public.user_challenges
  for select to authenticated using (user_id = (select auth.uid()));

-- Envio de foto: a pessoa informa apenas desafio, caminho da foto e comentário.
grant select, delete on public.challenge_submissions to authenticated;
grant insert (challenge_id, photo_path, note) on public.challenge_submissions to authenticated;
grant update (status, reviewed_by, reviewed_at) on public.challenge_submissions to authenticated;

create policy "le os proprios envios" on public.challenge_submissions
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy "envia a propria foto" on public.challenge_submissions
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    -- a foto precisa estar na pasta da própria pessoa no bucket privado
    and (photo_path is null or photo_path like (select auth.uid())::text || '/%')
  );
create policy "apaga os proprios envios" on public.challenge_submissions
  for delete to authenticated using (user_id = (select auth.uid()));
create policy "administracao modera envios" on public.challenge_submissions
  for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- ---------------------------------------------------------------------
-- CHEF IA
-- ---------------------------------------------------------------------
-- Conversas não são apagadas (apenas arquivadas) e mensagens não são editadas nem apagadas:
-- é o histórico de mensagens que sustenta o limite de uso.
grant select, insert on public.ai_conversations to authenticated;
grant update (title, archived_at, recipe_id) on public.ai_conversations to authenticated;
grant select, insert on public.ai_messages to authenticated;

create policy "le as proprias conversas" on public.ai_conversations
  for select to authenticated using (user_id = (select auth.uid()));
create policy "cria conversas com acesso valido" on public.ai_conversations
  for insert to authenticated
  with check (user_id = (select auth.uid()) and (select public.has_active_access()));
create policy "atualiza as proprias conversas" on public.ai_conversations
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "le as proprias mensagens" on public.ai_messages
  for select to authenticated using (user_id = (select auth.uid()));
create policy "grava mensagens nas proprias conversas" on public.ai_messages
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and (select public.has_active_access())
    and exists (select 1 from public.ai_conversations c where c.id = conversation_id and c.user_id = (select auth.uid()))
  );

-- ---------------------------------------------------------------------
-- COMERCIAL
-- ---------------------------------------------------------------------
-- Pedidos: o navegador só lê. Criação e mudança de situação acontecem no servidor (service_role).
grant select on public.orders to authenticated;
create policy "le os proprios pedidos" on public.orders
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));

grant select on public.payment_transactions to authenticated;
create policy "administracao le transacoes" on public.payment_transactions
  for select to authenticated using ((select public.is_admin()));

-- Acessos: a pessoa lê o próprio; administradores concedem cortesias e revogam.
grant select, insert, update on public.memberships to authenticated;
create policy "le o proprio acesso" on public.memberships
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy "administracao concede acesso" on public.memberships
  for insert to authenticated
  with check ((select public.is_admin()) and source in ('courtesy', 'admin'));
create policy "administracao altera acesso" on public.memberships
  for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- Auditoria: somente leitura para administradores; a escrita é feita por gatilhos.
grant select on public.admin_audit_logs to authenticated;
create policy "administracao le auditoria" on public.admin_audit_logs
  for select to authenticated using ((select public.is_admin()));
