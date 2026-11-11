-- =====================================================================
-- Clube da Ceia Perfeita — 01. Estrutura
-- Tabelas, relacionamentos, índices e timestamps.
-- Convenções: UUID em todas as chaves, created_at/updated_at, texto + CHECK
-- no lugar de ENUM (mais simples de evoluir em novas temporadas).
-- =====================================================================

create or replace function public.set_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------------
-- COMERCIAL: temporadas e perfis
-- ---------------------------------------------------------------------
create table public.seasons (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text,
  -- Situação administrativa. As janelas de venda e de acesso são definidas pelas datas abaixo.
  status text not null default 'draft' check (status in ('draft', 'active', 'archived')),
  price_cents integer check (price_cents is null or price_cents >= 0),
  currency text not null default 'BRL',
  sales_starts_at timestamptz,
  sales_ends_at timestamptz,
  access_starts_at timestamptz,
  access_ends_at timestamptz,
  admin_notice text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint seasons_sales_window check (sales_starts_at is null or sales_ends_at is null or sales_ends_at > sales_starts_at),
  constraint seasons_access_window check (access_starts_at is null or access_ends_at is null or access_ends_at > access_starts_at)
);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  full_name text not null default '',
  avatar_url text,
  -- A role só pode ser alterada por administradores (ver 02_funcoes e 03_seguranca).
  role text not null default 'customer' check (role in ('customer', 'admin')),
  preferences jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- CONTEÚDO: coleções, documentos de origem e receitas
-- ---------------------------------------------------------------------
create table public.collections (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text,
  cover_image text,
  -- 'catalog' = grade de receitas · 'builder' = experiência de montagem (ex.: Monte sua Rabanada)
  experience text not null default 'catalog' check (experience in ('catalog', 'builder')),
  position integer not null default 0,
  is_visible boolean not null default true,
  admin_notice text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.source_documents (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  collection_id uuid references public.collections (id) on delete set null,
  title text not null,
  author text,
  publisher text,
  file_name text,
  language text not null default 'pt-BR',
  page_count integer check (page_count is null or page_count > 0),
  -- not_provided: sem arquivo · awaiting_upload: nome conhecido, PDF não anexado
  -- received: analisado/importado · stored: arquivo guardado no bucket privado
  file_status text not null default 'not_provided' check (file_status in ('not_provided', 'awaiting_upload', 'received', 'stored')),
  storage_path text,
  sha256 text,
  -- Controle de permissão comercial: nada é publicado sem 'confirmed'.
  commercial_permission text not null default 'unknown' check (commercial_permission in ('unknown', 'confirmed', 'restricted', 'denied')),
  permission_notes text,
  permission_confirmed_by uuid references public.profiles (id) on delete set null,
  permission_confirmed_at timestamptz,
  measurement_notes text,
  import_notes text,
  toc jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index source_documents_collection_idx on public.source_documents (collection_id);

create table public.recipes (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  collection_id uuid not null references public.collections (id) on delete restrict,
  source_document_id uuid references public.source_documents (id) on delete set null,
  -- recipe: receita completa · component: parte reutilizável (massa, base, calda…)
  -- variation: variação combinável (ex.: recheio de rabanada)
  kind text not null default 'recipe' check (kind in ('recipe', 'component', 'variation')),
  component_role text check (component_role is null or component_role in ('base', 'massa', 'esponja', 'recheio', 'cobertura', 'calda', 'creme', 'montagem', 'finalizacao', 'fritura', 'outro')),
  flavor text check (flavor is null or flavor in ('doce', 'salgado')),
  title text not null,
  original_title text,
  original_language text not null default 'pt-BR',
  translation_status text not null default 'not_needed' check (translation_status in ('not_needed', 'pending', 'in_review', 'reviewed')),
  description text,
  cover_image text,
  difficulty text check (difficulty is null or difficulty in ('facil', 'media', 'dificil')),
  -- Rendimento original. servings fica NULO quando o material não informa porções.
  yield_quantity numeric check (yield_quantity is null or yield_quantity > 0),
  yield_unit text,
  yield_unit_plural text,
  yield_detail text,
  yield_text text,
  servings integer check (servings is null or servings > 0),
  prep_minutes integer check (prep_minutes is null or prep_minutes >= 0),
  cook_minutes integer check (cook_minutes is null or cook_minutes >= 0),
  bake_minutes integer check (bake_minutes is null or bake_minutes >= 0),
  chill_minutes integer check (chill_minutes is null or chill_minutes >= 0),
  rest_minutes integer check (rest_minutes is null or rest_minutes >= 0),
  chill_is_minimum boolean not null default false,
  measure_note text,
  source_page_start integer,
  source_page_end integer,
  source_pages_extra integer[] not null default '{}',
  page_ref_verified boolean not null default false,
  -- catalogued: identificada no índice, sem ficha · structured: ficha estruturada
  content_state text not null default 'catalogued' check (content_state in ('catalogued', 'structured')),
  status text not null default 'draft' check (status in ('draft', 'review', 'approved', 'published', 'pending_permission', 'archived')),
  position integer not null default 0,
  is_featured boolean not null default false,
  reviewed_by uuid references public.profiles (id) on delete set null,
  reviewed_at timestamptz,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index recipes_collection_idx on public.recipes (collection_id, position);
create index recipes_document_idx on public.recipes (source_document_id);
create index recipes_status_idx on public.recipes (status);

-- Partes de uma receita (massa, esponja, recheio, cobertura, calda, montagem, finalização…).
-- linked_recipe_id aponta para um componente compartilhado (recipes.kind = 'component'),
-- evitando duplicar ingredientes e etapas entre preparações.
create table public.recipe_components (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.recipes (id) on delete cascade,
  linked_recipe_id uuid references public.recipes (id) on delete restrict,
  role text not null default 'outro' check (role in ('base', 'massa', 'esponja', 'recheio', 'cobertura', 'calda', 'creme', 'montagem', 'finalizacao', 'fritura', 'outro')),
  title text not null,
  original_title text,
  description text,
  -- fração do componente compartilhado usada nesta receita (1 = receita inteira do componente)
  multiplier numeric not null default 1 check (multiplier > 0),
  position integer not null default 0,
  source_page_start integer,
  source_page_end integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint recipe_components_no_self_link check (linked_recipe_id is null or linked_recipe_id <> recipe_id)
);
create index recipe_components_recipe_idx on public.recipe_components (recipe_id, position);
create index recipe_components_linked_idx on public.recipe_components (linked_recipe_id);

create table public.ingredients (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  category text not null default 'outros',
  is_shoppable boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.recipe_ingredients (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.recipes (id) on delete cascade,
  component_id uuid references public.recipe_components (id) on delete cascade,
  ingredient_id uuid references public.ingredients (id) on delete restrict,
  position integer not null default 0,
  -- quantity NULA = medida textual (a gosto, QN, quantidade não informada)
  quantity numeric check (quantity is null or quantity >= 0),
  quantity_max numeric check (quantity_max is null or quantity_max >= 0),
  unit text,
  quantity_text text,
  display_name text not null,
  preparation text,
  household_note text,
  -- linear: proporcional · manual: exige validação culinária · fixed: não escala
  scaling text not null default 'linear' check (scaling in ('linear', 'manual', 'fixed')),
  is_optional boolean not null default false,
  original_text text,
  source_page integer,
  needs_review boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index recipe_ingredients_recipe_idx on public.recipe_ingredients (recipe_id, position);
create index recipe_ingredients_component_idx on public.recipe_ingredients (component_id);
create index recipe_ingredients_ingredient_idx on public.recipe_ingredients (ingredient_id);

create table public.recipe_steps (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.recipes (id) on delete cascade,
  component_id uuid references public.recipe_components (id) on delete cascade,
  position integer not null default 0,
  instruction text not null,
  original_text text,
  tip text,
  source_page integer,
  needs_review boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index recipe_steps_recipe_idx on public.recipe_steps (recipe_id, position);
create index recipe_steps_component_idx on public.recipe_steps (component_id);

-- O que cada etapa utiliza: um ingrediente da receita ou um componente já preparado.
create table public.recipe_step_ingredients (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.recipes (id) on delete cascade,
  step_id uuid not null references public.recipe_steps (id) on delete cascade,
  recipe_ingredient_id uuid references public.recipe_ingredients (id) on delete cascade,
  component_id uuid references public.recipe_components (id) on delete cascade,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  constraint recipe_step_ingredients_one_ref check (num_nonnulls(recipe_ingredient_id, component_id) = 1)
);
create index recipe_step_ingredients_recipe_idx on public.recipe_step_ingredients (recipe_id);
create index recipe_step_ingredients_step_idx on public.recipe_step_ingredients (step_id);

create table public.recipe_step_timers (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.recipes (id) on delete cascade,
  step_id uuid not null references public.recipe_steps (id) on delete cascade,
  label text not null,
  duration_seconds integer not null check (duration_seconds > 0),
  kind text not null default 'cook' check (kind in ('cook', 'bake', 'chill', 'rest', 'other')),
  is_minimum boolean not null default false,
  temperature_c integer,
  original_text text,
  needs_review boolean not null default false,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index recipe_step_timers_recipe_idx on public.recipe_step_timers (recipe_id);
create index recipe_step_timers_step_idx on public.recipe_step_timers (step_id);

-- Dicas, observações e equipamentos (conteúdo premium, por isso fora da tabela recipes).
create table public.recipe_notes (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.recipes (id) on delete cascade,
  kind text not null check (kind in ('tip', 'note', 'equipment')),
  title text,
  body text not null,
  original_text text,
  source_page integer,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index recipe_notes_recipe_idx on public.recipe_notes (recipe_id, kind, position);

create table public.recipe_tags (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.recipes (id) on delete cascade,
  tag text not null,
  created_at timestamptz not null default now(),
  unique (recipe_id, tag)
);
create index recipe_tags_tag_idx on public.recipe_tags (tag);

-- Combinações permitidas nas experiências de montagem (base × recheio × finalização).
create table public.recipe_compatibilities (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references public.recipes (id) on delete cascade,
  compatible_recipe_id uuid not null references public.recipes (id) on delete cascade,
  relation text not null default 'recheio',
  source_page integer,
  verified boolean not null default false,
  note text,
  created_at timestamptz not null default now(),
  unique (recipe_id, compatible_recipe_id),
  constraint recipe_compat_distinct check (recipe_id <> compatible_recipe_id)
);
create index recipe_compat_target_idx on public.recipe_compatibilities (compatible_recipe_id);

-- Campos destacados para revisão humana durante a importação.
create table public.review_flags (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid references public.recipes (id) on delete cascade,
  source_document_id uuid references public.source_documents (id) on delete cascade,
  entity text not null check (entity in ('recipe', 'component', 'ingredient', 'step', 'timer', 'note', 'document')),
  entity_id uuid,
  field text,
  severity text not null default 'warning' check (severity in ('info', 'warning', 'blocker')),
  message text not null,
  source_page integer,
  resolved_at timestamptz,
  resolved_by uuid references public.profiles (id) on delete set null,
  resolution_note text,
  created_at timestamptz not null default now(),
  constraint review_flags_target check (recipe_id is not null or source_document_id is not null)
);
create index review_flags_recipe_idx on public.review_flags (recipe_id);
create index review_flags_open_idx on public.review_flags (recipe_id) where resolved_at is null;

create table public.recipe_favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  recipe_id uuid not null references public.recipes (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, recipe_id)
);
create index recipe_favorites_recipe_idx on public.recipe_favorites (recipe_id);

-- ---------------------------------------------------------------------
-- PLANEJAMENTO
-- ---------------------------------------------------------------------
create table public.meal_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  season_id uuid references public.seasons (id) on delete set null,
  occasion text not null default 'natal' check (occasion in ('natal', 'ano_novo', 'outro')),
  title text not null,
  event_date date,
  serve_time time,
  guests integer not null default 8 check (guests between 1 and 200),
  notes text,
  -- folga de organização (min) usada pelo cronograma para etapas sem tempo cadastrado
  default_block_minutes integer not null default 30 check (default_block_minutes between 0 and 240),
  status text not null default 'active' check (status in ('active', 'done', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index meal_plans_user_idx on public.meal_plans (user_id, event_date);

create table public.plan_recipes (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.meal_plans (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  recipe_id uuid not null references public.recipes (id) on delete cascade,
  -- multiplicador sobre o rendimento original (1 = uma receita)
  factor numeric not null default 1 check (factor > 0 and factor <= 50),
  position integer not null default 0,
  notes text,
  builder_selection jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (plan_id, recipe_id)
);
create index plan_recipes_user_idx on public.plan_recipes (user_id);
create index plan_recipes_recipe_idx on public.plan_recipes (recipe_id);

create table public.plan_tasks (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.meal_plans (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  title text not null,
  kind text not null default 'custom' check (kind in ('default', 'schedule', 'custom')),
  ref_key text,
  due_at timestamptz,
  is_done boolean not null default false,
  done_at timestamptz,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (plan_id, ref_key)
);
create index plan_tasks_plan_idx on public.plan_tasks (plan_id, position);
create index plan_tasks_user_idx on public.plan_tasks (user_id);

create table public.shopping_lists (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  plan_id uuid references public.meal_plans (id) on delete set null,
  title text not null default 'Minha lista',
  is_default boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index shopping_lists_user_idx on public.shopping_lists (user_id);

create table public.shopping_items (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.shopping_lists (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  ingredient_id uuid references public.ingredients (id) on delete set null,
  name text not null,
  category text not null default 'outros',
  quantity numeric check (quantity is null or quantity >= 0),
  unit text,
  quantity_text text,
  is_checked boolean not null default false,
  checked_at timestamptz,
  is_manual boolean not null default false,
  quantity_edited boolean not null default false,
  -- de quais receitas veio cada parcela: [{recipe_id, recipe_title, quantity, unit, factor, plan_id}]
  sources jsonb not null default '[]'::jsonb,
  note text,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index shopping_items_list_idx on public.shopping_items (list_id, position);
create index shopping_items_user_idx on public.shopping_items (user_id);

create table public.cooking_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  recipe_id uuid not null references public.recipes (id) on delete cascade,
  plan_id uuid references public.meal_plans (id) on delete set null,
  factor numeric not null default 1 check (factor > 0 and factor <= 50),
  current_step integer not null default 0,
  completed_steps jsonb not null default '[]'::jsonb,
  status text not null default 'active' check (status in ('active', 'finished', 'abandoned')),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index cooking_sessions_user_idx on public.cooking_sessions (user_id, status);
create index cooking_sessions_recipe_idx on public.cooking_sessions (recipe_id);

-- ---------------------------------------------------------------------
-- GAMIFICAÇÃO E IA
-- ---------------------------------------------------------------------
create table public.challenges (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  season_id uuid references public.seasons (id) on delete set null,
  title text not null,
  description text,
  icon text,
  points integer not null default 10 check (points >= 0),
  badge_name text,
  badge_tier text check (badge_tier is null or badge_tier in ('bronze', 'prata', 'ouro')),
  rule_type text not null check (rule_type in ('cook_any', 'cook_in_collection', 'create_plan', 'complete_plan', 'shopping_done', 'favorites', 'chef_chat', 'manual')),
  rule_config jsonb not null default '{}'::jsonb,
  allows_photo boolean not null default true,
  is_active boolean not null default true,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_challenges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  challenge_id uuid not null references public.challenges (id) on delete cascade,
  progress integer not null default 0 check (progress >= 0),
  target integer not null default 1 check (target > 0),
  completed_at timestamptz,
  points_awarded integer not null default 0 check (points_awarded >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, challenge_id)
);
create index user_challenges_challenge_idx on public.user_challenges (challenge_id);

create table public.challenge_submissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  challenge_id uuid not null references public.challenges (id) on delete cascade,
  photo_path text,
  note text,
  status text not null default 'submitted' check (status in ('submitted', 'approved', 'rejected')),
  reviewed_by uuid references public.profiles (id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index challenge_submissions_user_idx on public.challenge_submissions (user_id);
create index challenge_submissions_challenge_idx on public.challenge_submissions (challenge_id);

create table public.ai_conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  title text,
  recipe_id uuid references public.recipes (id) on delete set null,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index ai_conversations_user_idx on public.ai_conversations (user_id, updated_at desc);

create table public.ai_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.ai_conversations (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null check (char_length(content) <= 8000),
  grounded_recipe_ids uuid[] not null default '{}',
  model text,
  tokens_in integer,
  tokens_out integer,
  created_at timestamptz not null default now()
);
create index ai_messages_conversation_idx on public.ai_messages (conversation_id, created_at);
create index ai_messages_usage_idx on public.ai_messages (user_id, created_at desc) where role = 'user';

-- ---------------------------------------------------------------------
-- COMERCIAL: pedidos, transações, acessos e auditoria
-- ---------------------------------------------------------------------
create table public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete restrict,
  season_id uuid not null references public.seasons (id) on delete restrict,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled', 'refunded', 'charged_back', 'in_mediation', 'review_required')),
  amount_cents integer not null check (amount_cents > 0),
  currency text not null default 'BRL',
  provider text not null default 'mercadopago',
  provider_preference_id text,
  provider_payment_id text,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index orders_user_idx on public.orders (user_id, created_at desc);
create index orders_season_idx on public.orders (season_id);

create table public.payment_transactions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete restrict,
  provider text not null default 'mercadopago',
  provider_payment_id text not null,
  status text not null,
  status_detail text,
  amount_cents integer,
  currency text,
  raw jsonb not null default '{}'::jsonb,
  seen_count integer not null default 1,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  -- cada combinação pagamento+situação é registrada uma única vez (webhook idempotente)
  unique (provider, provider_payment_id, status)
);
create index payment_transactions_order_idx on public.payment_transactions (order_id);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  season_id uuid not null references public.seasons (id) on delete restrict,
  status text not null default 'active' check (status in ('active', 'revoked')),
  source text not null default 'purchase' check (source in ('purchase', 'courtesy', 'admin')),
  order_id uuid references public.orders (id) on delete set null,
  granted_by uuid references public.profiles (id) on delete set null,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoke_reason text,
  -- true quando um administrador bloqueou manualmente: eventos de pagamento não reativam
  admin_locked boolean not null default false,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, season_id)
);
create index memberships_season_idx on public.memberships (season_id);
create index memberships_order_idx on public.memberships (order_id);

create table public.admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid,
  actor_email text,
  action text not null,
  entity text not null,
  entity_id text,
  summary text,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);
create index admin_audit_logs_created_idx on public.admin_audit_logs (created_at desc);
create index admin_audit_logs_entity_idx on public.admin_audit_logs (entity, entity_id);

-- ---------------------------------------------------------------------
-- updated_at automático
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'seasons', 'profiles', 'collections', 'source_documents', 'recipes', 'recipe_components', 'ingredients',
    'recipe_ingredients', 'recipe_steps', 'recipe_step_timers', 'recipe_notes', 'meal_plans', 'plan_recipes',
    'plan_tasks', 'shopping_lists', 'shopping_items', 'cooking_sessions', 'challenges', 'user_challenges',
    'challenge_submissions', 'ai_conversations', 'orders', 'memberships'
  ] loop
    execute format('create trigger set_updated_at before update on public.%I for each row execute function public.set_updated_at()', t);
  end loop;
end $$;
