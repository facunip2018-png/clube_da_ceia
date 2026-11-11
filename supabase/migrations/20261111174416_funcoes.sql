-- =====================================================================
-- Clube da Ceia Perfeita — 02. Funções e gatilhos
-- Regras de negócio que precisam valer no servidor, independentemente
-- do que o navegador enviar.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Auxiliares de identidade
-- ---------------------------------------------------------------------

-- Papel do token da requisição (anon, authenticated, service_role). Vazio fora da API.
create or replace function public.request_role() returns text
language sql stable set search_path = '' as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    ''
  );
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin'
  );
$$;

-- Acesso válido à temporada: administrador, ou membership ativa em temporada ativa
-- dentro da janela de acesso configurada.
create or replace function public.has_active_access() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin'
  ) or exists (
    select 1
    from public.memberships m
    join public.seasons s on s.id = m.season_id
    where m.user_id = (select auth.uid())
      and m.status = 'active'
      and s.status = 'active'
      and s.access_starts_at is not null
      and s.access_ends_at is not null
      and now() >= s.access_starts_at
      and now() < s.access_ends_at
      and (m.expires_at is null or m.expires_at > now())
  );
$$;

-- Resumo do acesso do usuário atual (usado pelo app para decidir o que exibir).
create or replace function public.my_access() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_is_admin boolean;
  v_row record;
begin
  if v_uid is null then
    return jsonb_build_object('authenticated', false, 'is_admin', false, 'has_access', false);
  end if;

  select (p.role = 'admin') into v_is_admin from public.profiles p where p.id = v_uid;
  v_is_admin := coalesce(v_is_admin, false);

  select s.id as season_id, s.name as season_name, s.access_ends_at, m.source
    into v_row
  from public.memberships m
  join public.seasons s on s.id = m.season_id
  where m.user_id = v_uid
    and m.status = 'active'
    and s.status = 'active'
    and s.access_starts_at is not null
    and s.access_ends_at is not null
    and now() >= s.access_starts_at
    and now() < s.access_ends_at
    and (m.expires_at is null or m.expires_at > now())
  order by s.access_ends_at desc
  limit 1;

  return jsonb_build_object(
    'authenticated', true,
    'is_admin', v_is_admin,
    'has_access', v_is_admin or v_row.season_id is not null,
    'season_id', v_row.season_id,
    'season_name', v_row.season_name,
    'access_until', v_row.access_ends_at,
    'source', v_row.source
  );
end $$;

-- Indicadores públicos do catálogo: somente contagens, calculadas dos registros reais.
create or replace function public.catalog_stats()
returns table (
  collection_id uuid,
  published_recipes integer,
  published_components integer,
  published_variations integer,
  in_preparation integer
)
language sql stable security definer set search_path = '' as $$
  select
    c.id,
    (count(*) filter (where r.status = 'published' and r.kind = 'recipe'))::integer,
    (count(*) filter (where r.status = 'published' and r.kind = 'component'))::integer,
    (count(*) filter (where r.status = 'published' and r.kind = 'variation'))::integer,
    (count(*) filter (where r.status in ('draft', 'review', 'approved', 'pending_permission')))::integer
  from public.collections c
  left join public.recipes r on r.collection_id = c.id
  where c.is_visible
  group by c.id;
$$;

-- ---------------------------------------------------------------------
-- Perfis: criação automática e proteção da role
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), ''))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.handle_user_email_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.email is distinct from old.email then
    update public.profiles set email = new.email where id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists on_auth_user_email_changed on auth.users;
create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row execute function public.handle_user_email_change();

-- Usuários que já existiam antes desta migration.
insert into public.profiles (id, email)
select u.id, u.email from auth.users u
on conflict (id) do nothing;

-- Defesa em profundidade: mesmo que alguém obtenha permissão de UPDATE na coluna,
-- a role só muda se quem pede for administrador (ou o próprio servidor/SQL Editor).
create or replace function public.guard_profile_role() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.role is distinct from old.role then
    if public.request_role() in ('authenticated', 'anon') and not public.is_admin() then
      raise exception 'ROLE_CHANGE_FORBIDDEN: apenas administradores podem alterar a role.' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

create trigger guard_profile_role
  before update on public.profiles
  for each row execute function public.guard_profile_role();

-- ---------------------------------------------------------------------
-- Auditoria
-- ---------------------------------------------------------------------
create or replace function public.write_audit_log(
  p_action text, p_entity text, p_entity_id text, p_summary text, p_old jsonb, p_new jsonb
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
begin
  if v_uid is not null then
    select p.email into v_email from public.profiles p where p.id = v_uid;
  end if;
  insert into public.admin_audit_logs (actor_id, actor_email, action, entity, entity_id, summary, old_data, new_data)
  values (v_uid, coalesce(v_email, case when v_uid is null then 'sistema' end), p_action, p_entity, p_entity_id, p_summary, p_old, p_new);
end $$;

-- Gatilho genérico de auditoria para tabelas administrativas.
create or replace function public.audit_row_change() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_action text;
  v_summary text;
  v_id text;
begin
  -- Cargas feitas por migrations/seed (sem usuário e sem token de API) não geram ruído no log.
  if auth.uid() is null and public.request_role() <> 'service_role' then
    return null;
  end if;

  if tg_op <> 'INSERT' then v_old := to_jsonb(old); end if;
  if tg_op <> 'DELETE' then v_new := to_jsonb(new); end if;
  v_id := coalesce(v_new ->> 'id', v_old ->> 'id');
  v_action := tg_table_name || '.' || case tg_op when 'INSERT' then 'created' when 'UPDATE' then 'updated' else 'deleted' end;

  if tg_op = 'UPDATE' then
    if (v_new - 'updated_at') = (v_old - 'updated_at') then
      return null;
    end if;

    if tg_table_name = 'profiles' then
      -- Em perfis só interessa a troca de role.
      if (v_new ->> 'role') is not distinct from (v_old ->> 'role') then
        return null;
      end if;
      v_action := 'profiles.role_changed';
      v_summary := format('%s: %s → %s', coalesce(v_new ->> 'email', v_id), v_old ->> 'role', v_new ->> 'role');
    elsif tg_table_name = 'recipes' and (v_new ->> 'status') is distinct from (v_old ->> 'status') then
      v_action := 'recipes.status_changed';
      v_summary := format('%s: %s → %s', v_new ->> 'title', v_old ->> 'status', v_new ->> 'status');
    elsif tg_table_name = 'source_documents' and (v_new ->> 'commercial_permission') is distinct from (v_old ->> 'commercial_permission') then
      v_action := 'source_documents.permission_changed';
      v_summary := format('%s: %s → %s', v_new ->> 'title', v_old ->> 'commercial_permission', v_new ->> 'commercial_permission');
    elsif tg_table_name = 'memberships' and (v_new ->> 'status') is distinct from (v_old ->> 'status') then
      v_action := 'memberships.' || (v_new ->> 'status');
      v_summary := coalesce(v_new ->> 'revoke_reason', v_new ->> 'source');
    elsif tg_table_name = 'review_flags' then
      if (v_new ->> 'resolved_at') is not distinct from (v_old ->> 'resolved_at') then
        return null;
      end if;
      v_action := case when v_new ->> 'resolved_at' is null then 'review_flags.reopened' else 'review_flags.resolved' end;
      v_summary := left(v_new ->> 'message', 160);
    end if;
  elsif tg_table_name in ('profiles', 'review_flags') then
    -- criação/remoção de perfis e flags não entra no log administrativo
    return null;
  end if;

  if v_summary is null then
    v_summary := coalesce(v_new ->> 'title', v_new ->> 'name', v_old ->> 'title', v_old ->> 'name');
  end if;

  perform public.write_audit_log(v_action, tg_table_name, v_id, v_summary, v_old, v_new);
  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array['collections', 'source_documents', 'recipes', 'seasons', 'challenges', 'memberships', 'profiles', 'review_flags'] loop
    execute format('create trigger audit_row_change after insert or update or delete on public.%I for each row execute function public.audit_row_change()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Fluxo editorial: draft → review → approved → published
-- ---------------------------------------------------------------------
create or replace function public.guard_recipe_status() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_permission text;
  v_changed boolean := (tg_op = 'INSERT') or (old.status is distinct from new.status);
begin
  if not v_changed then
    return new;
  end if;

  if new.status in ('approved', 'published') then
    if new.content_state <> 'structured' then
      raise exception 'CONTENT_REQUIRED: a receita ainda não possui ficha estruturada.' using errcode = 'P0001';
    end if;
    if exists (
      select 1 from public.review_flags f
      where f.recipe_id = new.id and f.resolved_at is null and f.severity in ('warning', 'blocker')
    ) then
      raise exception 'FLAGS_PENDING: existem pontos de revisão em aberto nesta ficha.' using errcode = 'P0001';
    end if;
  end if;

  if new.status = 'approved' then
    new.reviewed_at := now();
    new.reviewed_by := coalesce(auth.uid(), new.reviewed_by);
  end if;

  if new.status = 'published' then
    if new.reviewed_at is null then
      raise exception 'APPROVAL_REQUIRED: a ficha precisa ser aprovada na revisão antes de ser publicada.' using errcode = 'P0001';
    end if;
    select d.commercial_permission into v_permission
    from public.source_documents d where d.id = new.source_document_id;
    if v_permission is distinct from 'confirmed' then
      raise exception 'PERMISSION_REQUIRED: confirme a permissão comercial do documento de origem antes de publicar.' using errcode = 'P0001';
    end if;
    if exists (
      select 1
      from public.recipe_components rc
      join public.recipes lr on lr.id = rc.linked_recipe_id
      where rc.recipe_id = new.id and lr.status <> 'published'
    ) then
      raise exception 'LINKED_COMPONENT_UNPUBLISHED: publique antes os componentes compartilhados desta receita.' using errcode = 'P0001';
    end if;
    new.published_at := coalesce(new.published_at, now());
  end if;

  return new;
end $$;

create trigger guard_recipe_status
  before insert or update on public.recipes
  for each row execute function public.guard_recipe_status();

-- Permissão comercial do documento: registra quem confirmou e, se a permissão
-- deixar de estar confirmada, tira do ar as receitas daquele documento.
create or replace function public.before_document_permission_change() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.commercial_permission is distinct from old.commercial_permission then
    if new.commercial_permission = 'confirmed' then
      new.permission_confirmed_at := now();
      new.permission_confirmed_by := auth.uid();
    else
      new.permission_confirmed_at := null;
      new.permission_confirmed_by := null;
    end if;
  end if;
  return new;
end $$;

create trigger before_document_permission_change
  before update on public.source_documents
  for each row execute function public.before_document_permission_change();

create or replace function public.after_document_permission_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.commercial_permission is distinct from old.commercial_permission then
    if new.commercial_permission = 'confirmed' then
      -- libera o que estava bloqueado: volta para revisão (se já tinha sido revisado) ou rascunho
      update public.recipes r
        set status = case when r.reviewed_at is not null then 'review' else 'draft' end
      where r.source_document_id = new.id and r.status = 'pending_permission';
    else
      update public.recipes r
        set status = 'pending_permission'
      where r.source_document_id = new.id and r.status = 'published';
    end if;
  end if;
  return null;
end $$;

create trigger after_document_permission_change
  after update on public.source_documents
  for each row execute function public.after_document_permission_change();

-- recipe_id das tabelas filhas de etapa é sempre derivado da etapa (consistência + RLS simples).
create or replace function public.fill_step_child_recipe_id() returns trigger
language plpgsql set search_path = '' as $$
begin
  select s.recipe_id into new.recipe_id from public.recipe_steps s where s.id = new.step_id;
  if new.recipe_id is null then
    raise exception 'STEP_NOT_FOUND: etapa inexistente.' using errcode = '23503';
  end if;
  return new;
end $$;

create trigger fill_recipe_id before insert or update of step_id on public.recipe_step_timers
  for each row execute function public.fill_step_child_recipe_id();
create trigger fill_recipe_id before insert or update of step_id on public.recipe_step_ingredients
  for each row execute function public.fill_step_child_recipe_id();

-- ---------------------------------------------------------------------
-- Administração
-- ---------------------------------------------------------------------
create or replace function public.admin_set_role(p_user uuid, p_role text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN: apenas administradores.' using errcode = '42501';
  end if;
  if p_role not in ('customer', 'admin') then
    raise exception 'INVALID_ROLE' using errcode = '22023';
  end if;
  if p_user = auth.uid() and p_role <> 'admin' then
    raise exception 'SELF_DEMOTION: outro administrador precisa remover o seu acesso.' using errcode = '42501';
  end if;
  update public.profiles set role = p_role where id = p_user;
  if not found then
    raise exception 'USER_NOT_FOUND' using errcode = 'P0002';
  end if;
end $$;

create or replace function public.admin_usage_stats() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN: apenas administradores.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'users', (select count(*) from public.profiles),
    'active_memberships', (
      select count(*) from public.memberships m join public.seasons s on s.id = m.season_id
      where m.status = 'active' and s.status = 'active' and (s.access_ends_at is null or now() < s.access_ends_at)
    ),
    'orders_approved', (select count(*) from public.orders where status = 'approved'),
    'orders_pending', (select count(*) from public.orders where status = 'pending'),
    'revenue_cents', (select coalesce(sum(amount_cents), 0) from public.orders where status = 'approved'),
    'plans', (select count(*) from public.meal_plans),
    'cooking_sessions_finished', (select count(*) from public.cooking_sessions where status = 'finished'),
    'favorites', (select count(*) from public.recipe_favorites),
    'shopping_items', (select count(*) from public.shopping_items),
    'chef_messages', (select count(*) from public.ai_messages where role = 'user'),
    'chef_messages_7d', (select count(*) from public.ai_messages where role = 'user' and created_at > now() - interval '7 days'),
    'challenges_completed', (select count(*) from public.user_challenges where completed_at is not null),
    'top_favorites', (
      select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select r.title, count(*)::integer as total
        from public.recipe_favorites f join public.recipes r on r.id = f.recipe_id
        group by r.title order by count(*) desc, r.title limit 5
      ) x
    )
  );
end $$;

-- ---------------------------------------------------------------------
-- Desafios: o progresso é calculado no servidor a partir dos registros reais.
-- O usuário não escreve em user_challenges diretamente.
-- ---------------------------------------------------------------------
create or replace function public.refresh_my_challenges() returns setof public.user_challenges
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  c record;
  v_progress integer;
  v_target integer;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED' using errcode = '28000';
  end if;

  for c in select * from public.challenges where is_active loop
    v_target := greatest(coalesce(nullif(c.rule_config ->> 'target', '')::integer, 1), 1);

    v_progress := case c.rule_type
      when 'cook_any' then (
        select count(distinct s.recipe_id) from public.cooking_sessions s
        where s.user_id = v_uid and s.status = 'finished')
      when 'cook_in_collection' then (
        select count(distinct s.recipe_id)
        from public.cooking_sessions s
        join public.recipes r on r.id = s.recipe_id
        join public.collections col on col.id = r.collection_id
        where s.user_id = v_uid and s.status = 'finished' and col.slug = c.rule_config ->> 'collection_slug')
      when 'create_plan' then (
        select count(*) from public.meal_plans p
        where p.user_id = v_uid and p.event_date is not null
          and exists (select 1 from public.plan_recipes pr where pr.plan_id = p.id))
      when 'complete_plan' then (
        select count(*) from public.meal_plans p
        where p.user_id = v_uid
          and exists (select 1 from public.plan_tasks t where t.plan_id = p.id)
          and not exists (select 1 from public.plan_tasks t where t.plan_id = p.id and not t.is_done))
      when 'shopping_done' then (
        select count(*) from public.shopping_lists l
        where l.user_id = v_uid
          and (select count(*) from public.shopping_items i where i.list_id = l.id)
              >= greatest(coalesce(nullif(c.rule_config ->> 'min_items', '')::integer, 1), 1)
          and not exists (select 1 from public.shopping_items i where i.list_id = l.id and not i.is_checked))
      when 'favorites' then (
        select count(*) from public.recipe_favorites f where f.user_id = v_uid)
      when 'chef_chat' then (
        select count(*) from public.ai_messages m where m.user_id = v_uid and m.role = 'user')
      else null
    end;

    if v_progress is null then
      continue; -- desafios manuais não são calculados automaticamente
    end if;
    v_progress := least(v_progress, v_target);

    insert into public.user_challenges as uc (user_id, challenge_id, progress, target, completed_at, points_awarded)
    values (
      v_uid, c.id, v_progress, v_target,
      case when v_progress >= v_target then now() end,
      case when v_progress >= v_target then c.points else 0 end
    )
    on conflict (user_id, challenge_id) do update set
      -- conquista concluída permanece concluída
      progress = case when uc.completed_at is not null then uc.progress else excluded.progress end,
      target = case when uc.completed_at is not null then uc.target else excluded.target end,
      completed_at = coalesce(uc.completed_at, excluded.completed_at),
      points_awarded = case when uc.completed_at is not null then uc.points_awarded else excluded.points_awarded end;
  end loop;

  return query select * from public.user_challenges where user_id = v_uid;
end $$;

-- ---------------------------------------------------------------------
-- Pagamentos (Mercado Pago): processamento idempotente de um evento.
-- Chamado SOMENTE pelo servidor (service_role) depois de: validar a assinatura do
-- webhook, consultar o pagamento na API e conferir referência, valor e moeda.
-- Reaplicar o mesmo evento não muda o resultado.
-- ---------------------------------------------------------------------
create or replace function public.process_payment_event(
  p_order_id uuid,
  p_provider_payment_id text,
  p_status text,
  p_status_detail text,
  p_amount_cents integer,
  p_currency text,
  p_raw jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_order public.orders%rowtype;
  v_rows integer := 0;
  v_membership text := 'unchanged';
  v_is_main_payment boolean;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    return jsonb_build_object('result', 'order_not_found');
  end if;

  insert into public.payment_transactions as t
    (order_id, provider, provider_payment_id, status, status_detail, amount_cents, currency, raw)
  values
    (v_order.id, v_order.provider, p_provider_payment_id, p_status, p_status_detail, p_amount_cents,
     upper(coalesce(p_currency, '')), coalesce(p_raw, '{}'::jsonb))
  on conflict (provider, provider_payment_id, status)
  do update set seen_count = t.seen_count + 1, last_seen_at = now();

  v_is_main_payment := v_order.provider_payment_id is null or v_order.provider_payment_id = p_provider_payment_id;

  if p_status = 'approved' then
    -- Defesa em profundidade: valor e moeda precisam bater com o pedido.
    if p_amount_cents is distinct from v_order.amount_cents
       or upper(coalesce(p_currency, '')) <> upper(v_order.currency) then
      update public.orders set status = 'review_required' where id = v_order.id and status <> 'approved';
      perform public.write_audit_log(
        'orders.amount_mismatch', 'orders', v_order.id::text,
        format('Pagamento %s aprovado com valor ou moeda diferente do pedido', p_provider_payment_id),
        null,
        jsonb_build_object('expected_cents', v_order.amount_cents, 'received_cents', p_amount_cents,
                           'expected_currency', v_order.currency, 'received_currency', p_currency));
      return jsonb_build_object('result', 'amount_mismatch', 'order_status', 'review_required', 'membership', 'unchanged');
    end if;

    update public.orders
      set status = 'approved', paid_at = coalesce(paid_at, now()), provider_payment_id = p_provider_payment_id
    where id = v_order.id;

    insert into public.memberships as m (user_id, season_id, status, source, order_id, granted_at)
    values (v_order.user_id, v_order.season_id, 'active', 'purchase', v_order.id, now())
    on conflict (user_id, season_id) do update
      set status = 'active', source = 'purchase', order_id = excluded.order_id,
          revoked_at = null, revoke_reason = null
      where m.admin_locked = false
        and (m.status <> 'active' or m.order_id is distinct from excluded.order_id);
    get diagnostics v_rows = row_count;

    if v_rows > 0 then
      v_membership := 'granted';
    elsif exists (
      select 1 from public.memberships m
      where m.user_id = v_order.user_id and m.season_id = v_order.season_id and m.admin_locked
    ) then
      v_membership := 'locked_by_admin';
    end if;

  elsif p_status in ('refunded', 'charged_back') then
    -- Política: estorno ou contestação do pagamento principal revoga o acesso.
    if v_is_main_payment then
      update public.orders set status = p_status where id = v_order.id;
      update public.memberships
        set status = 'revoked', revoked_at = now(), revoke_reason = 'payment_' || p_status
      where order_id = v_order.id and status = 'active';
      get diagnostics v_rows = row_count;
      if v_rows > 0 then v_membership := 'revoked'; end if;
    end if;

  elsif p_status = 'in_mediation' then
    -- Política: disputa aberta sinaliza o pedido, mas mantém o acesso até a decisão.
    if v_is_main_payment then
      update public.orders set status = 'in_mediation' where id = v_order.id and status in ('approved', 'pending');
    end if;

  elsif p_status in ('rejected', 'cancelled') then
    -- Tentativa que falhou só altera pedidos ainda pendentes (uma nova tentativa pode ser aprovada).
    update public.orders set status = p_status where id = v_order.id and status = 'pending';
  end if;

  return jsonb_build_object(
    'result', 'applied',
    'order_status', (select o.status from public.orders o where o.id = v_order.id),
    'membership', v_membership
  );
end $$;
