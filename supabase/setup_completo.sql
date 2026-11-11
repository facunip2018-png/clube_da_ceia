-- =====================================================================
-- Clube da Ceia Perfeita — instalação completa do banco (GERADO)
-- Cole este arquivo inteiro no SQL Editor do Supabase de um projeto NOVO e execute uma vez.
-- Conteúdo: 5 migrations + carga inicial (supabase/seed.sql).
-- Para projetos que já rodaram as migrations, execute apenas supabase/seed.sql.
-- =====================================================================

-- >>>>>>>>>> migrations/20261111174214_schema.sql
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

-- >>>>>>>>>> migrations/20261111174416_funcoes.sql
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

-- >>>>>>>>>> migrations/20261111174526_seguranca.sql
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

-- >>>>>>>>>> migrations/20261111174549_storage.sql
-- =====================================================================
-- Clube da Ceia Perfeita — 04. Storage
--   source-documents  (privado)  PDFs originais dos e-books — somente administradores
--   challenge-photos  (privado)  fotos enviadas nos desafios — cada pessoa na própria pasta
--   recipe-images     (público)  capas de receitas e coleções enviadas pelo admin
-- =====================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('source-documents', 'source-documents', false, 52428800, array['application/pdf'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('challenge-photos', 'challenge-photos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('recipe-images', 'recipe-images', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- PDFs originais: nunca públicos. Leitura e escrita apenas para administradores.
create policy "pdfs originais: somente administradores"
  on storage.objects for all to authenticated
  using (bucket_id = 'source-documents' and (select public.is_admin()))
  with check (bucket_id = 'source-documents' and (select public.is_admin()));

-- Fotos dos desafios: cada pessoa lê, envia e apaga dentro de <user_id>/…
create policy "fotos de desafios: pasta propria (leitura)"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'challenge-photos'
    and ((storage.foldername(name))[1] = (select auth.uid())::text or (select public.is_admin()))
  );

create policy "fotos de desafios: pasta propria (envio)"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'challenge-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "fotos de desafios: pasta propria (remocao)"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'challenge-photos'
    and ((storage.foldername(name))[1] = (select auth.uid())::text or (select public.is_admin()))
  );

-- Capas: leitura pública pelo próprio bucket; escrita apenas para administradores.
create policy "capas: administradores enviam"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'recipe-images' and (select public.is_admin()));

create policy "capas: administradores atualizam"
  on storage.objects for update to authenticated
  using (bucket_id = 'recipe-images' and (select public.is_admin()))
  with check (bucket_id = 'recipe-images' and (select public.is_admin()));

create policy "capas: administradores removem"
  on storage.objects for delete to authenticated
  using (bucket_id = 'recipe-images' and (select public.is_admin()));

-- >>>>>>>>>> migrations/20261111180506_storage_capas_select.sql
-- =====================================================================
-- Clube da Ceia Perfeita — 05. Storage: capas (ajuste)
-- A API do Storage precisa de SELECT para listar, substituir (upsert) e
-- remover arquivos. Sem esta policy, administradores conseguiam enviar
-- capas para recipe-images, mas não removê-las nem substituí-las
-- (encontrado no teste contra o projeto hospedado: tests/hosted/smoke.mjs).
-- A leitura pública das capas continua sendo feita pela URL pública do bucket.
-- =====================================================================

create policy "capas: administradores listam"
  on storage.objects for select to authenticated
  using (bucket_id = 'recipe-images' and (select public.is_admin()));

-- >>>>>>>>>> seed.sql
-- =====================================================================
-- Clube da Ceia Perfeita — carga de conteúdo (GERADO por scripts/content-build.mjs)
-- Não edite à mão: altere os arquivos em content/ e rode `npm run content:build`.
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
insert into public.seasons (id, slug, name, description, status, price_cents, currency, sales_starts_at, sales_ends_at, access_starts_at, access_ends_at, admin_notice) values
  ('083900e2-ca8a-5618-9445-d65989d06ebc', 'natal-ano-novo-2026', 'Natal & Ano-Novo 2026', 'Coleções especiais para preparar, organizar e celebrar.', 'draft', null, 'BRL', '2026-11-01T03:00:00Z', '2027-01-01T02:59:59Z', '2026-11-01T03:00:00Z', '2027-02-01T02:59:59Z', 'Datas sugeridas (horário de Brasília) e preço NÃO definidos pelo projeto: ajuste no painel administrativo e mude a situação para “ativa” para abrir vendas e acesso.')
on conflict (slug) do nothing;

-- Coleções
insert into public.collections (id, slug, name, description, cover_image, experience, position, is_visible, admin_notice) values
  ('baadf930-32cf-54ee-9242-59f7f1bc55d8', 'panetones-chocotones', 'Panetones & Chocotones', 'Massas tradicionais, versões recheadas, trufadas e coberturas para a temporada de Natal.', '/images/col-panetones.jpg', 'catalog', 1, true, 'O PDF contém receitas de massas, esponjas, recheios, coberturas, montagem, utensílios e dicas. Cada preparação deve ter ficha própria, relacionada aos componentes compartilhados (massa, esponja, recheio, cobertura).'),
  ('2c014300-260b-53cb-a40e-fab8781d1dad', 'rabanadas-recheadas', 'Rabanadas Recheadas', 'Monte a sua: escolha a base, o recheio e a finalização entre versões doces e salgadas.', '/images/col-rabanadas.jpg', 'builder', 2, true, 'Segundo o levantamento do MVP, o próprio PDF informa restrições de reprodução, cópia, alteração e distribuição comercial sem autorização prévia. As fichas ficam bloqueadas (pending_permission) até a licença ser confirmada.'),
  ('429a72fd-5f48-5b8b-bb59-02f2d613a2ef', 'paves', 'Pavês', 'Clássicos e combinações de chocolate, frutas, café e cremes para servir gelados.', '/images/col-paves.jpg', 'catalog', 3, true, 'A coleção reúne onze receitas do Recetario Gourmet (com partes em espanhol, tradução sujeita a revisão) e o Pavê Floresta Negra, de um PDF separado.'),
  ('ea73175e-a31a-5b97-8955-dc6096c4f30f', 'tortas-doces', 'Tortas Doces', 'Tortas para diferentes gostos, com opções cremosas, frutadas, de chocolate e nozes.', '/images/col-tortas.jpg', 'catalog', 4, true, 'O material usa xícara de 240 ml como medida principal. Preservar as medidas originais e separar massa, recheio e cobertura na ficha.'),
  ('cd1626cc-d0b8-5816-9bb4-d5445f4de6cf', 'manjar-de-coco', 'Manjar de Coco', 'A sobremesa clássica de coco, em breve no seu caderno.', '/images/col-manjar.jpg', 'catalog', 5, true, 'PDF ainda não recebido. Coleção preparada, sem receitas cadastradas. Não inventar receitas nem quantidades.'),
  ('08cb0c28-cc0e-5b03-abc2-293be8a44f76', 'pudins', 'Pudins', 'O pudim de leite condensado e futuras variações, em breve no seu caderno.', '/images/col-pudins.jpg', 'catalog', 6, true, 'PDF do Pudim de Leite Condensado ainda não recebido. Coleção preparada, sem receitas cadastradas. Não inventar receitas nem quantidades.')
on conflict (slug) do nothing;

-- Documentos de origem
insert into public.source_documents (id, slug, collection_id, title, author, publisher, file_name, language, page_count, file_status, storage_path, sha256, commercial_permission, permission_notes, measurement_notes, import_notes, toc) values
  ('00135c34-aa9a-5715-98cb-6af65cfc83f6', 'panetones-chocotones-natal', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', 'Receitas criativas de panetones e chocotones para o Natal', null, null, 'receitas-criativas-de-panetones-e-chocotones-para-o-natal.pdf', 'pt-BR', null, 'awaiting_upload', null, null, 'unknown', null, null, 'PDF ainda não anexado a esta base. O sumário identifica 25 preparações (lista e páginas vindas do MVP, a confirmar no PDF). O material traz também dicas, utensílios, massas, esponjas, recheios, coberturas e montagens: cada preparação deve ter ficha própria ligada aos componentes compartilhados.', '[]'::jsonb),
  ('9f1834ff-9e61-54b7-aaa5-c09bc034f1b0', 'rabanadas-recheadas-dcc-2021', '2c014300-260b-53cb-a40e-fab8781d1dad', 'Rabanadas Recheadas D&CC (2021)', null, null, 'rabanadas-recheadas-d-amp-cc-2021.pdf', 'pt-BR', null, 'awaiting_upload', null, null, 'restricted', 'Segundo o levantamento do MVP, o próprio PDF informa restrições de reprodução, cópia, alteração e distribuição comercial sem autorização prévia. Não publicar ingredientes ou etapas sem licença confirmada.', null, 'PDF ainda não anexado a esta base. Estruturar como experiência "Monte sua Rabanada": bases (pão doce/salgado), calda, fritura, recheios doces e salgados e finalizações, respeitando as combinações do material. Criar fichas de componentes e receitas combinadas somente depois de analisar o documento completo.', '[]'::jsonb),
  ('3a4a09a2-e60d-58ff-bc8f-3bb9217ff12b', 'recetario-gourmet-paves', '429a72fd-5f48-5b8b-bb59-02f2d613a2ef', 'Recetario Gourmet — 11 recetas de pavê', null, null, '11-receta-de-pave-completo-y-revisado.pdf', 'es', null, 'awaiting_upload', null, null, 'unknown', null, null, 'PDF ainda não anexado a esta base. Possui partes em espanhol: traduzir títulos, ingredientes e instruções para pt-BR mantendo a referência ao texto original e encaminhar a tradução para revisão administrativa. Não converter medidas automaticamente sem validação.', '[]'::jsonb),
  ('78bdc3dc-b4a3-5f2d-ab98-face3f488038', 'pave-floresta-negra-valeria-ribeiro', '429a72fd-5f48-5b8b-bb59-02f2d613a2ef', 'Pavê Floresta Negra', 'Valéria Ribeiro', 'Dona Lú Doces — confeitaria artesanal', 'receita-de-pave-floresta-negra-com-creme-danete-uma-sobremesa-natalina-leve-e-saborosa.pdf', 'pt-BR', 11, 'received', null, '1d7d5bac78cc1026bd98f8b1a4b158f25532dd02c2a33b9376b13a377c98e2f2', 'unknown', 'O PDF identifica a autora (Valéria Ribeiro) e a marca (Dona Lú Doces) e não traz termo de licença de uso. Confirme a permissão comercial antes de publicar a ficha.', null, 'Importado em 10/11/2026 a partir do PDF anexado (11 páginas, texto extraído e conferido visualmente página a página; a página 7 contém apenas fotografia). As referências usam a página física do arquivo.', '[{"title":"Creme Danete","printed_page":4,"pdf_page":4},{"title":"Ingredientes Montagem","printed_page":5,"pdf_page":6},{"title":"Montagem","printed_page":7,"pdf_page":8},{"title":"Marcas que usamos","printed_page":8,"pdf_page":9},{"title":"Embalagem","printed_page":9,"pdf_page":10}]'::jsonb),
  ('48d7904c-48c4-5e7e-9d71-c3f89a3a0026', 'tortas-doces', 'ea73175e-a31a-5b97-8955-dc6096c4f30f', 'Apostila de Tortas Doces', null, null, 'tortas-doces.pdf', 'pt-BR', null, 'awaiting_upload', null, null, 'unknown', null, 'Neste material, 1 xícara = 240 ml.', 'PDF ainda não anexado a esta base. O índice identifica 15 preparações (lista e páginas vindas do MVP, a confirmar no PDF). Preservar as medidas originais, inclusive xícaras de 240 ml. Quando houver massa, recheio e cobertura, organizar as partes separadamente.', '[]'::jsonb),
  ('c5e12b34-123a-51f0-b400-744064e4d191', 'manjar-de-coco', 'cd1626cc-d0b8-5816-9bb4-d5445f4de6cf', 'Manjar de Coco (material a receber)', null, null, null, 'pt-BR', null, 'not_provided', null, null, 'unknown', null, null, 'PDF ainda não enviado. Não inventar receitas nem quantidades.', '[]'::jsonb),
  ('928998d2-fdc6-5e22-b958-060adcba24e2', 'pudim-de-leite-condensado', '08cb0c28-cc0e-5b03-abc2-293be8a44f76', 'Pudim de Leite Condensado (material a receber)', null, null, null, 'pt-BR', null, 'not_provided', null, null, 'unknown', null, null, 'PDF ainda não enviado. Não inventar receitas nem quantidades.', '[]'::jsonb)
on conflict (slug) do update set
  file_status = excluded.file_status, page_count = excluded.page_count, sha256 = excluded.sha256,
  author = coalesce(public.source_documents.author, excluded.author),
  publisher = coalesce(public.source_documents.publisher, excluded.publisher),
  toc = excluded.toc, import_notes = excluded.import_notes
  where public.source_documents.file_status in ('not_provided', 'awaiting_upload')
    and excluded.file_status in ('received', 'stored');

-- Ingredientes (catálogo para a lista de compras)
insert into public.ingredients (id, slug, name, category, is_shoppable) values
  ('6b34b876-9b3f-5612-96da-1abcf6f11bbc', 'leite-condensado', 'Leite condensado', 'laticinios', true),
  ('8758d73e-4fcf-508e-940d-635708436a41', 'creme-de-leite-uht', 'Creme de leite (caixinha)', 'laticinios', true),
  ('d964c7ff-936f-5900-a359-d5733e3c5c8c', 'creme-de-leite-fresco', 'Creme de leite fresco', 'laticinios', true),
  ('ea4555e0-c258-513c-9d9a-3d81eb730e6a', 'leite', 'Leite', 'laticinios', true),
  ('ba6fe174-cf59-5fcc-b16e-1c364477c3e5', 'chocolate-em-po', 'Chocolate em pó', 'mercearia', true),
  ('f2b0542e-4276-5937-aa27-615636db24fe', 'acucar-refinado', 'Açúcar refinado', 'mercearia', true),
  ('d17cd146-1603-5e80-b6a6-1a423f48a032', 'bolacha-champanhe', 'Bolacha champanhe', 'mercearia', true),
  ('cc3f3495-b6ac-5141-abf0-824166cf67a1', 'cerejas-em-calda', 'Cerejas em calda', 'mercearia', true),
  ('93677461-72d8-561f-9001-581dee2a7cc4', 'cerejas-frescas', 'Cerejas frescas', 'hortifruti', true),
  ('4296956f-ddbc-517f-85d5-7a9b1ff85d6a', 'granule', 'Granulé', 'confeitaria', true),
  ('9d5e30fb-7933-5db6-a243-31fd6989b797', 'brigadeiros', 'Brigadeiros', 'confeitaria', true),
  ('f5c19bc6-2479-5ec4-9abe-d4aceecc1f8e', 'agua', 'Água', 'despensa', false)
on conflict (slug) do nothing;

-- Desafios
insert into public.challenges (id, slug, season_id, title, description, icon, points, badge_name, badge_tier, rule_type, rule_config, allows_photo, is_active, position) values
  ('5027dd12-3467-5c28-b074-812aeb540124', 'primeiro-panetone', null, 'Prepare seu primeiro panetone', 'Conclua no modo cozinheiro uma receita da coleção Panetones & Chocotones.', 'croissant', 30, 'Mãos na massa', 'prata', 'cook_in_collection', '{"collection_slug":"panetones-chocotones","target":1}'::jsonb, true, true, 1),
  ('bbd185c3-00bf-5f72-ad6d-590819a26629', 'primeira-rabanada', null, 'Faça sua primeira rabanada', 'Monte e conclua uma rabanada recheada da coleção.', 'sandwich', 30, 'Rabanada de ouro', 'prata', 'cook_in_collection', '{"collection_slug":"rabanadas-recheadas","target":1}'::jsonb, true, true, 2),
  ('538d5e29-5e32-59a4-bf39-b96158cbbd3f', 'sobremesa-especial', null, 'Prepare uma sobremesa especial', 'Conclua qualquer receita do Clube no modo cozinheiro.', 'cake', 20, 'Primeira sobremesa', 'bronze', 'cook_any', '{"target":1}'::jsonb, true, true, 3),
  ('b7902478-63b7-509f-96e6-01875f76e3a7', 'tres-receitas', null, 'Complete três receitas', 'Conclua três receitas diferentes no modo cozinheiro.', 'chef-hat', 50, 'Chef da temporada', 'ouro', 'cook_any', '{"target":3}'::jsonb, true, true, 4),
  ('ad1e3135-c583-5ffb-bf53-072fd4c0f5b3', 'organize-sua-ceia', null, 'Organize sua ceia', 'Crie um planejamento com data, convidados e pelo menos uma receita.', 'calendar', 20, 'Anfitrião organizado', 'bronze', 'create_plan', '{"target":1}'::jsonb, false, true, 5),
  ('756d6739-91c5-515a-968c-dbd9ed33df09', 'conclua-seu-planejamento', null, 'Conclua seu planejamento', 'Marque como concluídas todas as tarefas do checklist de uma ceia.', 'list-checks', 40, 'Ceia sem correria', 'ouro', 'complete_plan', '{"target":1}'::jsonb, false, true, 6),
  ('47353b5d-f386-5e7e-8b9c-5f74f40d9d90', 'organize-as-compras', null, 'Organize as compras', 'Marque como comprados todos os itens da sua lista (com pelo menos cinco itens).', 'shopping-basket', 20, 'Despensa em dia', 'bronze', 'shopping_done', '{"min_items":5}'::jsonb, false, true, 7),
  ('87e01068-9527-5e28-835f-08c7ea6b19fd', 'salve-suas-favoritas', null, 'Salve suas favoritas', 'Guarde três receitas na sua seleção de favoritas.', 'heart', 10, 'Curadoria pessoal', 'bronze', 'favorites', '{"target":3}'::jsonb, false, true, 8),
  ('e0958f74-24d5-5bef-b2fe-f664496fe6b1', 'converse-com-o-chef', null, 'Converse com o Chef', 'Envie sua primeira pergunta ao Chef IA.', 'sparkles', 10, 'Curiosidade de chef', 'bronze', 'chef_chat', '{"target":1}'::jsonb, false, true, 9)
on conflict (slug) do nothing;

-- Receitas catalogadas (título + página a confirmar; sem ficha)
insert into public.recipes (id, slug, collection_id, source_document_id, kind, component_role, flavor, title, original_title, original_language, translation_status, description, cover_image, difficulty, yield_quantity, yield_unit, yield_unit_plural, yield_detail, yield_text, servings, prep_minutes, cook_minutes, bake_minutes, chill_minutes, rest_minutes, chill_is_minimum, measure_note, source_page_start, source_page_end, source_pages_extra, page_ref_verified, content_state, status, position, is_featured) values
  ('d2ff7c98-1883-52ee-8f1d-b725b581dca4', 'panetone-tradicional', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Panetone Tradicional', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 18, null, '{}'::integer[], false, 'catalogued', 'draft', 1, false),
  ('bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'chocotone-tradicional', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone Tradicional', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 22, null, '{}'::integer[], false, 'catalogued', 'draft', 2, false),
  ('f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'chocotone-de-churros', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone de Churros', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 25, null, '{}'::integer[], false, 'catalogued', 'draft', 3, false),
  ('f9435243-097a-5129-8c21-10874bac99c9', 'chocotone-de-ninho', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone de Ninho', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 29, null, '{}'::integer[], false, 'catalogued', 'draft', 4, false),
  ('bc22d3a4-d37b-5496-8975-1a7ee0adc383', 'chocotone-ferrero-rocher', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone Ferrero Rocher', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 33, null, '{}'::integer[], false, 'catalogued', 'draft', 5, false),
  ('1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', 'chocotone-de-brigadeiro', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone de Brigadeiro', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 37, null, '{}'::integer[], false, 'catalogued', 'draft', 6, false),
  ('c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'panetone-de-morango', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Panetone de Morango', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 41, null, '{}'::integer[], false, 'catalogued', 'draft', 7, false),
  ('f162e20a-72c7-544c-b8dc-77abfd74956a', 'panetone-trufado-de-maracuja', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Panetone Trufado de Maracujá', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 45, null, '{}'::integer[], false, 'catalogued', 'draft', 8, false),
  ('d2af5983-6d59-57ab-b58b-0aabfa5e6c82', 'chocotone-trufado', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone Trufado', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 49, null, '{}'::integer[], false, 'catalogued', 'draft', 9, false),
  ('ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'chocotone-ovomaltine', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone Ovomaltine', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 53, null, '{}'::integer[], false, 'catalogued', 'draft', 10, false),
  ('ceb882d2-0dba-55b5-88d1-89c8e9991514', 'chocotone-de-brigadeiro-gourmet', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone de Brigadeiro Gourmet', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 57, null, '{}'::integer[], false, 'catalogued', 'draft', 11, false),
  ('3e9a4b0a-d7f0-5047-ac81-784a3e737d71', 'chocotone-de-nutella', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone de Nutella', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 61, null, '{}'::integer[], false, 'catalogued', 'draft', 12, false),
  ('8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', 'chocotone-de-coco', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone de Coco', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 65, null, '{}'::integer[], false, 'catalogued', 'draft', 13, false),
  ('402d03c4-696f-5a06-bc57-60887ac4e688', 'chocotone-de-oreo', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone de Oreo', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 69, null, '{}'::integer[], false, 'catalogued', 'draft', 14, false),
  ('adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'chocotone-2-amores', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone 2 Amores', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 73, null, '{}'::integer[], false, 'catalogued', 'draft', 15, false),
  ('6a8c669b-816b-5cf2-9774-2d16d24209bb', 'panetone-de-nozes', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Panetone de Nozes', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 77, null, '{}'::integer[], false, 'catalogued', 'draft', 16, false),
  ('1c9854b0-80e8-539a-af7a-579821d382c9', 'panetone-de-doce-de-leite-com-ameixas', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Panetone de Doce de Leite com Ameixas', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 81, null, '{}'::integer[], false, 'catalogued', 'draft', 17, false),
  ('155006a3-77a9-5248-bca7-a7624fc3795d', 'chocotone-laka', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone Laka', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 85, null, '{}'::integer[], false, 'catalogued', 'draft', 18, false),
  ('7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', 'panetone-com-cobertura-natalina', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Panetone com Cobertura Natalina', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 89, null, '{}'::integer[], false, 'catalogued', 'draft', 19, false),
  ('3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'chocotone-dressed', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone Dressed', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 93, null, '{}'::integer[], false, 'catalogued', 'draft', 20, false),
  ('4d2a3954-117b-5bba-bc3f-d10f8fae417d', 'chocotone-alpino', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone Alpino', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 97, null, '{}'::integer[], false, 'catalogued', 'draft', 21, false),
  ('dc77b330-46fd-5257-afaa-235c8c5915f4', 'chocotone-kinder-bueno', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone Kinder Bueno', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 101, null, '{}'::integer[], false, 'catalogued', 'draft', 22, false),
  ('d4a503e9-6658-5cc1-9ff8-f27a4f989268', 'panetone-red-velvet-com-recheio-de-limao', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Panetone Red Velvet com Recheio de Limão', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 105, null, '{}'::integer[], false, 'catalogued', 'draft', 23, false),
  ('9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'chocotone-infantil', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone Infantil', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 109, null, '{}'::integer[], false, 'catalogued', 'draft', 24, false),
  ('47d81496-9268-5d71-9e83-4475e751a3af', 'panetone-chocotone-no-pote', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Panetone/Chocotone no Pote', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 113, null, '{}'::integer[], false, 'catalogued', 'draft', 25, false),
  ('9c27ffa3-a66a-5507-93b8-3a48706455d3', 'pave-de-chocolate', '429a72fd-5f48-5b8b-bb59-02f2d613a2ef', '3a4a09a2-e60d-58ff-bc8f-3bb9217ff12b', 'recipe', null, null, 'Pavê de Chocolate', null, 'es', 'pending', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 3, null, '{}'::integer[], false, 'catalogued', 'draft', 1, false),
  ('e19479eb-5570-54cf-9514-5dda0128e22e', 'pave-de-chocolate-bis', '429a72fd-5f48-5b8b-bb59-02f2d613a2ef', '3a4a09a2-e60d-58ff-bc8f-3bb9217ff12b', 'recipe', null, null, 'Pavê de Chocolate BIS', null, 'es', 'pending', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 5, null, '{}'::integer[], false, 'catalogued', 'draft', 2, false),
  ('14f0de2a-a52f-512d-a9a0-4ba0af50f9ba', 'pave-de-limao', '429a72fd-5f48-5b8b-bb59-02f2d613a2ef', '3a4a09a2-e60d-58ff-bc8f-3bb9217ff12b', 'recipe', null, null, 'Pavê de Limão', null, 'es', 'pending', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 6, null, '{}'::integer[], false, 'catalogued', 'draft', 3, false),
  ('b4afeac0-64b4-5cf3-a13d-3cc2be778e36', 'pave-de-pessego', '429a72fd-5f48-5b8b-bb59-02f2d613a2ef', '3a4a09a2-e60d-58ff-bc8f-3bb9217ff12b', 'recipe', null, null, 'Pavê de Pêssego', null, 'es', 'pending', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 7, null, '{}'::integer[], false, 'catalogued', 'draft', 4, false),
  ('dcf2abd6-4a7d-5198-b870-a6ab059f0989', 'pave-de-abacaxi', '429a72fd-5f48-5b8b-bb59-02f2d613a2ef', '3a4a09a2-e60d-58ff-bc8f-3bb9217ff12b', 'recipe', null, null, 'Pavê de Abacaxi', null, 'es', 'pending', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 9, null, '{}'::integer[], false, 'catalogued', 'draft', 5, false),
  ('df378a63-a01b-5f4c-a691-ca32dbff83b0', 'pave-de-maracuja-e-chocolate', '429a72fd-5f48-5b8b-bb59-02f2d613a2ef', '3a4a09a2-e60d-58ff-bc8f-3bb9217ff12b', 'recipe', null, null, 'Pavê de Maracujá e Chocolate', null, 'es', 'pending', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 10, null, '{}'::integer[], false, 'catalogued', 'draft', 6, false),
  ('7fa0fb39-f48e-59d3-adff-cd35f4ceacac', 'pave-de-uva-chocolate-e-chantilly', '429a72fd-5f48-5b8b-bb59-02f2d613a2ef', '3a4a09a2-e60d-58ff-bc8f-3bb9217ff12b', 'recipe', null, null, 'Pavê de Uva, Chocolate e Chantilly', null, 'es', 'pending', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 11, null, '{}'::integer[], false, 'catalogued', 'draft', 7, false),
  ('e134f87d-086a-582a-8a15-c2d066c95f27', 'pave-de-amendoim', '429a72fd-5f48-5b8b-bb59-02f2d613a2ef', '3a4a09a2-e60d-58ff-bc8f-3bb9217ff12b', 'recipe', null, null, 'Pavê de Amendoim', null, 'es', 'pending', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 13, null, '{}'::integer[], false, 'catalogued', 'draft', 8, false),
  ('d5fe9f74-0576-5ea9-8b1c-81bee54cd50e', 'pave-de-ameixa', '429a72fd-5f48-5b8b-bb59-02f2d613a2ef', '3a4a09a2-e60d-58ff-bc8f-3bb9217ff12b', 'recipe', null, null, 'Pavê de Ameixa', null, 'es', 'pending', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 14, null, '{}'::integer[], false, 'catalogued', 'draft', 9, false),
  ('f8249532-a781-5bc4-a92e-29c81d84cd5a', 'pave-de-cafe', '429a72fd-5f48-5b8b-bb59-02f2d613a2ef', '3a4a09a2-e60d-58ff-bc8f-3bb9217ff12b', 'recipe', null, null, 'Pavê de Café', null, 'es', 'pending', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 15, null, '{}'::integer[], false, 'catalogued', 'draft', 10, false),
  ('e8167929-1a5c-59db-9494-0e3d55eb0fe3', 'pave-de-chocolate-branco', '429a72fd-5f48-5b8b-bb59-02f2d613a2ef', '3a4a09a2-e60d-58ff-bc8f-3bb9217ff12b', 'recipe', null, null, 'Pavê de Chocolate Branco', null, 'es', 'pending', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 16, null, '{}'::integer[], false, 'catalogued', 'draft', 11, false),
  ('a7b40dde-6f46-549e-b241-d1f2ce57b967', 'pao-para-rabanada-doce', '2c014300-260b-53cb-a40e-fab8781d1dad', '9f1834ff-9e61-54b7-aaa5-c09bc034f1b0', 'component', 'base', 'doce', 'Pão para Rabanada Doce', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 8, null, '{}'::integer[], false, 'catalogued', 'pending_permission', 1, false),
  ('d2b5efd4-b9bd-52ae-ad0a-b61c455d5526', 'pao-para-rabanada-salgada', '2c014300-260b-53cb-a40e-fab8781d1dad', '9f1834ff-9e61-54b7-aaa5-c09bc034f1b0', 'component', 'base', 'salgado', 'Pão para Rabanada Salgada', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 9, null, '{}'::integer[], false, 'catalogued', 'pending_permission', 2, false),
  ('0d32a443-044d-5b39-bcba-98c64b01f4d5', 'preparacao-da-calda', '2c014300-260b-53cb-a40e-fab8781d1dad', '9f1834ff-9e61-54b7-aaa5-c09bc034f1b0', 'component', 'calda', null, 'Preparação da Calda', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, null, null, '{}'::integer[], false, 'catalogued', 'pending_permission', 3, false),
  ('55634b07-66b8-577d-a0f3-37e5665ac12a', 'processo-de-fritura', '2c014300-260b-53cb-a40e-fab8781d1dad', '9f1834ff-9e61-54b7-aaa5-c09bc034f1b0', 'component', 'fritura', null, 'Processo de Fritura', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, null, null, '{}'::integer[], false, 'catalogued', 'pending_permission', 4, false),
  ('3344a33a-cd35-50c6-b5cc-b4a5a7172aa3', 'rabanada-doce-recheada-com-nutella', '2c014300-260b-53cb-a40e-fab8781d1dad', '9f1834ff-9e61-54b7-aaa5-c09bc034f1b0', 'variation', 'recheio', 'doce', 'Rabanada Doce Recheada com Nutella', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 14, null, '{}'::integer[], false, 'catalogued', 'pending_permission', 5, false),
  ('e046b77b-53ae-553d-a48e-46cc549b2c3f', 'rabanada-doce-recheada-com-doce-de-leite', '2c014300-260b-53cb-a40e-fab8781d1dad', '9f1834ff-9e61-54b7-aaa5-c09bc034f1b0', 'variation', 'recheio', 'doce', 'Rabanada Doce Recheada com Doce de Leite', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 15, null, '{}'::integer[], false, 'catalogued', 'pending_permission', 6, false),
  ('a1727205-c664-5885-8fbf-1b493ab3b56f', 'rabanada-doce-com-brigadeiro-de-nozes', '2c014300-260b-53cb-a40e-fab8781d1dad', '9f1834ff-9e61-54b7-aaa5-c09bc034f1b0', 'variation', 'recheio', 'doce', 'Rabanada Doce com Brigadeiro de Nozes', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 16, null, '{}'::integer[], false, 'catalogued', 'pending_permission', 7, false),
  ('767a747e-c223-5375-901f-ff6252db5054', 'rabanada-salgada-com-gorgonzola-nozes-e-damasco', '2c014300-260b-53cb-a40e-fab8781d1dad', '9f1834ff-9e61-54b7-aaa5-c09bc034f1b0', 'variation', 'recheio', 'salgado', 'Rabanada Salgada com Gorgonzola, Nozes e Damasco', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 18, null, '{}'::integer[], false, 'catalogued', 'pending_permission', 8, false),
  ('d9e29f1e-cf44-5b21-bc7e-7af045cdd5fa', 'rabanada-salgada-com-salame-e-ricota', '2c014300-260b-53cb-a40e-fab8781d1dad', '9f1834ff-9e61-54b7-aaa5-c09bc034f1b0', 'variation', 'recheio', 'salgado', 'Rabanada Salgada com Salame e Ricota', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 20, null, '{}'::integer[], false, 'catalogued', 'pending_permission', 9, false),
  ('3a87e780-858a-5e60-9807-636e0e5f38aa', 'rabanada-salgada-com-peito-de-peru-e-queijo', '2c014300-260b-53cb-a40e-fab8781d1dad', '9f1834ff-9e61-54b7-aaa5-c09bc034f1b0', 'variation', 'recheio', 'salgado', 'Rabanada Salgada com Peito de Peru e Queijo', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 22, null, '{}'::integer[], false, 'catalogued', 'pending_permission', 10, false),
  ('1ac9e920-e610-5df9-b7db-8678e9a6832b', 'torta-de-chocolate', 'ea73175e-a31a-5b97-8955-dc6096c4f30f', '48d7904c-48c4-5e7e-9d71-c3f89a3a0026', 'recipe', null, null, 'Torta de Chocolate', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 2, null, '{}'::integer[], false, 'catalogued', 'draft', 1, false),
  ('494db6c3-630d-50c7-aa94-5ed2b32faa55', 'torta-de-banana-e-coco', 'ea73175e-a31a-5b97-8955-dc6096c4f30f', '48d7904c-48c4-5e7e-9d71-c3f89a3a0026', 'recipe', null, null, 'Torta de Banana e Coco', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 3, null, '{}'::integer[], false, 'catalogued', 'draft', 2, false),
  ('a0af0186-5593-5c49-b484-9d61de9b5bda', 'torta-de-chantilly-com-maracuja', 'ea73175e-a31a-5b97-8955-dc6096c4f30f', '48d7904c-48c4-5e7e-9d71-c3f89a3a0026', 'recipe', null, null, 'Torta de Chantilly com Maracujá', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 4, null, '{}'::integer[], false, 'catalogued', 'draft', 3, false),
  ('ea49384c-50e7-533c-9ff6-640ccb4290c7', 'torta-de-ameixa-com-nozes', 'ea73175e-a31a-5b97-8955-dc6096c4f30f', '48d7904c-48c4-5e7e-9d71-c3f89a3a0026', 'recipe', null, null, 'Torta de Ameixa com Nozes', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 5, null, '{}'::integer[], false, 'catalogued', 'draft', 4, false),
  ('8b4bb2cf-853e-5349-ac5f-fe1b4b1a206a', 'torta-de-limao', 'ea73175e-a31a-5b97-8955-dc6096c4f30f', '48d7904c-48c4-5e7e-9d71-c3f89a3a0026', 'recipe', null, null, 'Torta de Limão', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 6, null, '{}'::integer[], false, 'catalogued', 'draft', 5, false),
  ('ff428800-85e9-5f6d-8ebd-508c35d984df', 'torta-doce-de-milho', 'ea73175e-a31a-5b97-8955-dc6096c4f30f', '48d7904c-48c4-5e7e-9d71-c3f89a3a0026', 'recipe', null, null, 'Torta Doce de Milho', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 7, null, '{}'::integer[], false, 'catalogued', 'draft', 6, false),
  ('822eb3dd-4713-573e-8829-1e9d345a104f', 'torta-holandesa', 'ea73175e-a31a-5b97-8955-dc6096c4f30f', '48d7904c-48c4-5e7e-9d71-c3f89a3a0026', 'recipe', null, null, 'Torta Holandesa', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 8, null, '{}'::integer[], false, 'catalogued', 'draft', 7, false),
  ('b4bb649c-195c-5198-a188-f89e58eb3985', 'torta-mousse-de-mel', 'ea73175e-a31a-5b97-8955-dc6096c4f30f', '48d7904c-48c4-5e7e-9d71-c3f89a3a0026', 'recipe', null, null, 'Torta Mousse de Mel', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 9, null, '{}'::integer[], false, 'catalogued', 'draft', 8, false),
  ('8c612041-19d4-5f43-bc24-4eb8628141af', 'torta-de-manga', 'ea73175e-a31a-5b97-8955-dc6096c4f30f', '48d7904c-48c4-5e7e-9d71-c3f89a3a0026', 'recipe', null, null, 'Torta de Manga', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 10, null, '{}'::integer[], false, 'catalogued', 'draft', 9, false),
  ('440ab890-8804-5646-85e9-510bb46c78bf', 'torta-romeu-e-julieta', 'ea73175e-a31a-5b97-8955-dc6096c4f30f', '48d7904c-48c4-5e7e-9d71-c3f89a3a0026', 'recipe', null, null, 'Torta Romeu e Julieta', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 11, null, '{}'::integer[], false, 'catalogued', 'draft', 10, false),
  ('ea70da34-bf24-569a-b31d-5076eafb62f9', 'torta-de-nozes', 'ea73175e-a31a-5b97-8955-dc6096c4f30f', '48d7904c-48c4-5e7e-9d71-c3f89a3a0026', 'recipe', null, null, 'Torta de Nozes', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 12, null, '{}'::integer[], false, 'catalogued', 'draft', 11, false),
  ('c7c87956-ca24-5912-9eb9-5bb9c9536ba0', 'torta-integral', 'ea73175e-a31a-5b97-8955-dc6096c4f30f', '48d7904c-48c4-5e7e-9d71-c3f89a3a0026', 'recipe', null, null, 'Torta Integral', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 13, null, '{}'::integer[], false, 'catalogued', 'draft', 12, false),
  ('9c288b62-3536-59d3-adb7-3f62e6b8dede', 'torta-de-pera', 'ea73175e-a31a-5b97-8955-dc6096c4f30f', '48d7904c-48c4-5e7e-9d71-c3f89a3a0026', 'recipe', null, null, 'Torta de Pêra', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 14, null, '{}'::integer[], false, 'catalogued', 'draft', 13, false),
  ('319d7675-e834-5cc2-9621-e5cf18cb7d24', 'torta-sorvete-de-cafe', 'ea73175e-a31a-5b97-8955-dc6096c4f30f', '48d7904c-48c4-5e7e-9d71-c3f89a3a0026', 'recipe', null, null, 'Torta Sorvete de Café', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 15, null, '{}'::integer[], false, 'catalogued', 'draft', 14, false),
  ('10a4557f-1e76-542e-8336-f351cdf0fc48', 'torta-de-maca', 'ea73175e-a31a-5b97-8955-dc6096c4f30f', '48d7904c-48c4-5e7e-9d71-c3f89a3a0026', 'recipe', null, null, 'Torta de Maçã', null, 'pt-BR', 'not_needed', null, null, null, null, null, null, null, null, null, null, null, null, null, null, false, null, 16, null, '{}'::integer[], false, 'catalogued', 'draft', 15, false)
on conflict (slug) do nothing;

-- Receitas com ficha estruturada
insert into public.recipes (id, slug, collection_id, source_document_id, kind, component_role, flavor, title, original_title, original_language, translation_status, description, cover_image, difficulty, yield_quantity, yield_unit, yield_unit_plural, yield_detail, yield_text, servings, prep_minutes, cook_minutes, bake_minutes, chill_minutes, rest_minutes, chill_is_minimum, measure_note, source_page_start, source_page_end, source_pages_extra, page_ref_verified, content_state, status, position, is_featured) values
  ('480e2ce8-4ca0-5937-901c-dfd4635b091a', 'pave-floresta-negra-com-creme-danete', '429a72fd-5f48-5b8b-bb59-02f2d613a2ef', '78bdc3dc-b4a3-5f2d-ab98-face3f488038', 'recipe', null, null, 'Pavê Floresta Negra com Creme Danete', 'PAVÊ FLORESTA NEGRA', 'pt-BR', 'not_needed', 'Sobremesa leve e saborosa para o cardápio de Natal. Na montagem vão bolacha champanhe, creme de leite fresco, cerejas em calda e o creme danete, com finalização de granulé, brigadeiros e cerejas frescas.', '/images/rec-pave-floresta-negra.jpg', null, 1, 'travessa', 'travessas', '27 × 17 cm', '1 travessa de 27 × 17 cm', null, null, null, null, 360, null, true, null, 4, 8, '{3,9,10}'::integer[], true, 'structured', 'review', 12, true)
on conflict (slug) do update set
  collection_id = excluded.collection_id, source_document_id = excluded.source_document_id, kind = excluded.kind, component_role = excluded.component_role, flavor = excluded.flavor, title = excluded.title, original_title = excluded.original_title, original_language = excluded.original_language, translation_status = excluded.translation_status, description = excluded.description, cover_image = excluded.cover_image, difficulty = excluded.difficulty, yield_quantity = excluded.yield_quantity, yield_unit = excluded.yield_unit, yield_unit_plural = excluded.yield_unit_plural, yield_detail = excluded.yield_detail, yield_text = excluded.yield_text, servings = excluded.servings, prep_minutes = excluded.prep_minutes, cook_minutes = excluded.cook_minutes, bake_minutes = excluded.bake_minutes, chill_minutes = excluded.chill_minutes, rest_minutes = excluded.rest_minutes, chill_is_minimum = excluded.chill_is_minimum, measure_note = excluded.measure_note, source_page_start = excluded.source_page_start, source_page_end = excluded.source_page_end, source_pages_extra = excluded.source_pages_extra, page_ref_verified = excluded.page_ref_verified, content_state = excluded.content_state, status = excluded.status, position = excluded.position, is_featured = excluded.is_featured
  where public.recipes.content_state = 'catalogued';


-- Ficha: Pavê Floresta Negra com Creme Danete
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = '480e2ce8-4ca0-5937-901c-dfd4635b091a')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = '480e2ce8-4ca0-5937-901c-dfd4635b091a')
     and not exists (select 1 from public.recipe_steps where recipe_id = '480e2ce8-4ca0-5937-901c-dfd4635b091a') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('97bbecb1-608a-5219-8519-5ef8ae9aade4', '480e2ce8-4ca0-5937-901c-dfd4635b091a', null, 'creme', 'Creme Danete', 'CREME DANETE', null, 1, 1, 4, 5),
      ('471e84da-373a-5090-9bd4-0b543fc8d751', '480e2ce8-4ca0-5937-901c-dfd4635b091a', null, 'recheio', 'Preparo para a montagem', 'INGREDIENTES PARA MONTAGEM', 'Chantilly com cerejas e pré-preparo dos ingredientes da montagem.', 1, 2, 6, 6),
      ('467019ad-814f-521c-8b0b-658df85d2d0e', '480e2ce8-4ca0-5937-901c-dfd4635b091a', null, 'montagem', 'Montagem', 'MONTAGEM', 'Monte as camadas do pavê seguindo a sequência abaixo.', 1, 3, 8, 8)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('34afd7b6-edd5-5ca4-b4cc-46db7f321400', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '97bbecb1-608a-5219-8519-5ef8ae9aade4', '6b34b876-9b3f-5612-96da-1abcf6f11bbc', 1, 600, null, 'g', null, 'leite condensado', null, '1 lata e meia', 'linear', false, '600g de leite condensado (1 lata e meia)', 4, false),
      ('d4e6f993-6f74-5261-b542-937afb118e12', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '97bbecb1-608a-5219-8519-5ef8ae9aade4', '8758d73e-4fcf-508e-940d-635708436a41', 2, 400, null, 'g', null, 'creme de leite', null, '2 caixinhas', 'linear', false, '400g de creme de leite (2 caixinha)', 4, false),
      ('348a92c1-e868-5767-92bd-f719b42769f7', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '97bbecb1-608a-5219-8519-5ef8ae9aade4', 'ba6fe174-cf59-5fcc-b16e-1c364477c3e5', 3, 100, null, 'g', null, 'chocolate em pó', null, null, 'linear', false, '100g chocolate em pó', 4, false),
      ('2cb9dc01-fdfc-507d-b822-38d9a9b8c942', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '97bbecb1-608a-5219-8519-5ef8ae9aade4', 'f5c19bc6-2479-5ec4-9abe-d4aceecc1f8e', 4, 75, null, 'ml', null, 'água', 'para diluir o chocolate', null, 'linear', false, '75ml de água para diluir o chocolate', 4, false),
      ('6c07feab-c6cd-52ae-ad7c-084e323d5a49', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '471e84da-373a-5090-9bd4-0b543fc8d751', 'd17cd146-1603-5e80-b6a6-1a423f48a032', 1, 1, null, 'pacote', null, 'bolacha champanhe', null, null, 'manual', false, '1 pacote de bolacha champanhe', 6, true),
      ('4b8da763-b8cf-52f2-86ef-63e92ffaaa8f', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '471e84da-373a-5090-9bd4-0b543fc8d751', 'd964c7ff-936f-5900-a359-d5733e3c5c8c', 2, 300, null, 'ml', null, 'creme de leite fresco', null, null, 'linear', false, '300ml de creme de leite fresco', 6, false),
      ('699e1341-b20f-5c1a-8ee6-3630e5018017', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '471e84da-373a-5090-9bd4-0b543fc8d751', 'f2b0542e-4276-5937-aa27-615636db24fe', 3, 30, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '30g de açúcar refinado', 6, false),
      ('400b141e-12ff-5361-8a6e-4310cb9c2cef', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '471e84da-373a-5090-9bd4-0b543fc8d751', 'cc3f3495-b6ac-5141-abf0-824166cf67a1', 4, 200, null, 'g', null, 'cerejas em calda', null, null, 'linear', false, '200g de cerejas em calda', 6, false),
      ('b49c100c-020a-5cca-ae4a-978c9bf28a7f', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '471e84da-373a-5090-9bd4-0b543fc8d751', '93677461-72d8-561f-9001-581dee2a7cc4', 5, 50, null, 'g', null, 'cerejas frescas', 'para decorar', null, 'linear', false, '50g de cerjas frescas para decorar', 6, false),
      ('ed6e4db8-c459-5d51-9be0-7efcfc919ac5', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '471e84da-373a-5090-9bd4-0b543fc8d751', 'ea4555e0-c258-513c-9d9a-3d81eb730e6a', 6, 500, null, 'ml', null, 'leite', 'para umedecer as bolachas', null, 'linear', false, '500ml de leite para umedecer  as bolachas', 6, false),
      ('a2a3eb26-f9bb-5f55-8483-4d1035860f5f', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '467019ad-814f-521c-8b0b-658df85d2d0e', '4296956f-ddbc-517f-85d5-7a9b1ff85d6a', 1, null, null, null, 'quantidade não informada', 'granulé', null, null, 'fixed', false, 'Finalize com granullé, brigadeiros e cerejas frescas', 8, true),
      ('b7a430f3-9735-5d10-9e30-80791f111691', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '467019ad-814f-521c-8b0b-658df85d2d0e', '9d5e30fb-7933-5db6-a243-31fd6989b797', 2, null, null, null, 'quantidade não informada', 'brigadeiros', null, null, 'fixed', false, 'Finalize com granullé, brigadeiros e cerejas frescas', 8, true)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('52874498-6d25-5a7d-adf9-35044994d620', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '97bbecb1-608a-5219-8519-5ef8ae9aade4', 1, 'Dilua o chocolate em pó na água.', '1 - Dilua o chocolate em pó na água.', null, 5, false),
      ('bbb0f191-231a-50d9-bb7e-f3d64bf2e728', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '97bbecb1-608a-5219-8519-5ef8ae9aade4', 2, 'Junte todos os ingredientes em uma panela de fundo grosso e misture bem.', '2 - Junte todos os ingredientes um uma panela de fundo grosso e misture bem.', null, 5, false),
      ('b7325563-9cef-5a85-9d28-deba51b0b075', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '97bbecb1-608a-5219-8519-5ef8ae9aade4', 3, 'Leve ao fogo e mexa até ferver, depois que ferver mexa por mais 4 minutos e retire do fogo.', '3 - Leve ao fogo e mexa até ferver, depois que ferver mexa por mais 4 minutos e retire do fogo.', null, 5, false),
      ('4460bf81-c984-5976-a650-9a0d0ccd7772', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '97bbecb1-608a-5219-8519-5ef8ae9aade4', 4, 'Transfira para uma vasilha, coloque um plástico filme em contato direto com creme e leve para gelar por pelo menos 6h.', '4 - Transfira para uma vasilha, coloque um plástico filme em contato direto com creme e leve para gelar por pelo menos 6h.', null, 5, false),
      ('21a84866-1310-55cc-85a6-3bd09a2d787b', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '97bbecb1-608a-5219-8519-5ef8ae9aade4', 5, 'Utilize depois de frio na montagem do pavê.', '5 - Utilize depois de frio na montagem do pavê.', null, 5, false),
      ('bc8ec5e7-d77f-5d87-8fc0-d7e100103e73', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '471e84da-373a-5090-9bd4-0b543fc8d751', 1, 'Reserve a bolacha champanhe.', '1. Reserve a bolacha champanhe', null, 6, false),
      ('161423dd-8880-51ab-8afc-70d9849630a8', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '471e84da-373a-5090-9bd4-0b543fc8d751', 2, 'Higienize as cerejas frescas.', '2. Higienize as cerejas frescas', null, 6, false),
      ('7fff0772-a441-5ae2-9c84-91d73dc15320', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '471e84da-373a-5090-9bd4-0b543fc8d751', 3, 'Pique as cerejas em calda em 4 partes. Reserve algumas inteiras para cortar ao meio e decorar a parede da travessa.', '3. Pique as cerejas em calda em 4 partes. Reserve algumas inteiras para cortar ao meio e decorar a parede da travessa', null, 6, false),
      ('0f02ffa6-e15a-55ba-a71c-3eb687e34282', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '471e84da-373a-5090-9bd4-0b543fc8d751', 4, 'Na batedeira coloque o creme de leite fresco com o açúcar refinado, misture e bata até formar chantilly.', '4. Na batedeira coloque o creme de leite fresco com o áçucar refinado, misture e bata até formar chantilly', null, 6, false),
      ('80adb6e7-fb9b-5531-9561-6e754603d3c0', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '471e84da-373a-5090-9bd4-0b543fc8d751', 5, 'Junte as cerejas picadas com chantilly e misture. Reserve para a montagem.', '5. Junte as cerejas picadas com chantilly e misture. Reserve para a montagem', null, 6, false),
      ('ea93868b-59ef-5414-baa8-9adfe37e4c4f', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '467019ad-814f-521c-8b0b-658df85d2d0e', 1, '1ª camada: creme danete.', '1. Creme danete', null, 8, false),
      ('aae33d34-ca6b-5a54-9d7d-25616eac43fb', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '467019ad-814f-521c-8b0b-658df85d2d0e', 2, '2ª camada: bolachas champanhe umedecidas no leite.', '2. Bolachas champanhe umedecidas no leite', null, 8, false),
      ('19ed8703-a95b-546a-9626-b05a5dd53257', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '467019ad-814f-521c-8b0b-658df85d2d0e', 3, '3ª camada: chantilly com cerejas.', '3. Chantilly com cerejas', null, 8, false),
      ('cd808922-f848-56fb-a983-e859a2511f7f', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '467019ad-814f-521c-8b0b-658df85d2d0e', 4, '4ª camada: bolachas champanhe umedecidas no leite.', '4. Bolachas champanhe umedecidas no leite', null, 8, false),
      ('f066562b-625e-5ac1-ade8-fd5ad7a352c5', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '467019ad-814f-521c-8b0b-658df85d2d0e', 5, '5ª camada: creme danete.', '5. Creme danete', null, 8, false),
      ('d661c40d-c916-5501-9deb-e24560195cba', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '467019ad-814f-521c-8b0b-658df85d2d0e', 6, 'Finalize com granulé, brigadeiros e cerejas frescas.', '6. Finalize com granullé, brigadeiros e cerejas frescas', null, 8, false)
    on conflict (id) do nothing;
    insert into public.recipe_step_ingredients (id, recipe_id, step_id, recipe_ingredient_id, component_id, position) values
      ('4d30dc87-ccb5-56d2-aab1-3881fa4c8175', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '52874498-6d25-5a7d-adf9-35044994d620', '348a92c1-e868-5767-92bd-f719b42769f7', null, 1),
      ('a23f4cff-d3c3-5f1f-ac94-74b13a1e081e', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '52874498-6d25-5a7d-adf9-35044994d620', '2cb9dc01-fdfc-507d-b822-38d9a9b8c942', null, 2),
      ('2ae0c30b-da52-581e-b573-3933ec23adc7', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'bbb0f191-231a-50d9-bb7e-f3d64bf2e728', '34afd7b6-edd5-5ca4-b4cc-46db7f321400', null, 1),
      ('2d0d7621-d237-596a-9667-61e4ab264e34', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'bbb0f191-231a-50d9-bb7e-f3d64bf2e728', 'd4e6f993-6f74-5261-b542-937afb118e12', null, 2),
      ('eff0650c-5d12-5551-be33-0d2dd11b4f1e', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'bbb0f191-231a-50d9-bb7e-f3d64bf2e728', '348a92c1-e868-5767-92bd-f719b42769f7', null, 3),
      ('f6662233-8807-5dfc-b384-a2669675533d', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'bbb0f191-231a-50d9-bb7e-f3d64bf2e728', '2cb9dc01-fdfc-507d-b822-38d9a9b8c942', null, 4),
      ('a19a2567-115d-591c-9830-476572aa21a3', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'bc8ec5e7-d77f-5d87-8fc0-d7e100103e73', '6c07feab-c6cd-52ae-ad7c-084e323d5a49', null, 1),
      ('d0e7168f-27bf-54a8-a3a5-5716e00eabac', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '161423dd-8880-51ab-8afc-70d9849630a8', 'b49c100c-020a-5cca-ae4a-978c9bf28a7f', null, 1),
      ('53de801b-0207-59fa-9e84-f864fcfa3e2c', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '7fff0772-a441-5ae2-9c84-91d73dc15320', '400b141e-12ff-5361-8a6e-4310cb9c2cef', null, 1),
      ('2404b0c7-930f-560f-b7a6-4656ea23a06f', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '0f02ffa6-e15a-55ba-a71c-3eb687e34282', '4b8da763-b8cf-52f2-86ef-63e92ffaaa8f', null, 1),
      ('efc59b38-89a1-56d5-8485-68fd66947158', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '0f02ffa6-e15a-55ba-a71c-3eb687e34282', '699e1341-b20f-5c1a-8ee6-3630e5018017', null, 2),
      ('59ed0647-38a6-53cf-bac8-8837e582c6b6', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '80adb6e7-fb9b-5531-9561-6e754603d3c0', '400b141e-12ff-5361-8a6e-4310cb9c2cef', null, 1),
      ('73432e9e-5655-5c24-913d-b275f56026ec', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'ea93868b-59ef-5414-baa8-9adfe37e4c4f', null, '97bbecb1-608a-5219-8519-5ef8ae9aade4', 1),
      ('4dbbd22f-4093-5ef1-b4c3-d7631bf9d391', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'aae33d34-ca6b-5a54-9d7d-25616eac43fb', '6c07feab-c6cd-52ae-ad7c-084e323d5a49', null, 1),
      ('fff4ba1c-bc47-565a-bc1a-d0920801fabe', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'aae33d34-ca6b-5a54-9d7d-25616eac43fb', 'ed6e4db8-c459-5d51-9be0-7efcfc919ac5', null, 2),
      ('ab5ab681-5e05-5c34-a67b-1c43f1c4ddd8', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '19ed8703-a95b-546a-9626-b05a5dd53257', null, '471e84da-373a-5090-9bd4-0b543fc8d751', 1),
      ('a6191609-1b29-506a-aa86-c550da2ddea0', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'cd808922-f848-56fb-a983-e859a2511f7f', '6c07feab-c6cd-52ae-ad7c-084e323d5a49', null, 1),
      ('65b0884d-6768-5f93-a8a3-7e5bff0e8989', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'cd808922-f848-56fb-a983-e859a2511f7f', 'ed6e4db8-c459-5d51-9be0-7efcfc919ac5', null, 2),
      ('5d1332c2-cc83-508e-abc0-627f64e83401', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'f066562b-625e-5ac1-ade8-fd5ad7a352c5', null, '97bbecb1-608a-5219-8519-5ef8ae9aade4', 1),
      ('7943f42b-646f-505b-89a9-147efe0d8eda', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'd661c40d-c916-5501-9deb-e24560195cba', 'a2a3eb26-f9bb-5f55-8483-4d1035860f5f', null, 1),
      ('2f7ebf05-5620-51c1-a1b1-0804af6be76f', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'd661c40d-c916-5501-9deb-e24560195cba', 'b7a430f3-9735-5d10-9e30-80791f111691', null, 2),
      ('0af6f660-3436-5b3d-8d96-f0b7b1a43f81', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'd661c40d-c916-5501-9deb-e24560195cba', 'b49c100c-020a-5cca-ae4a-978c9bf28a7f', null, 3)
    on conflict (id) do nothing;
    insert into public.recipe_step_timers (id, recipe_id, step_id, label, duration_seconds, kind, is_minimum, temperature_c, original_text, needs_review, position) values
      ('b4b25d7e-0286-5dd2-8917-1d8451ccf344', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'b7325563-9cef-5a85-9d28-deba51b0b075', 'Mexer após ferver', 240, 'cook', false, null, 'depois que ferver mexa por mais 4 minutos', false, 1),
      ('c879508c-3c60-550f-91c1-216f85535f0d', '480e2ce8-4ca0-5937-901c-dfd4635b091a', '4460bf81-c984-5976-a650-9a0d0ccd7772', 'Geladeira — creme danete', 21600, 'chill', true, null, 'leve para gelar por pelo menos 6h', false, 1)
    on conflict (id) do nothing;
    insert into public.recipe_notes (id, recipe_id, kind, title, body, original_text, source_page, position) values
      ('2b86c1ac-7d99-5f5a-8482-6ce57bb1c976', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'tip', null, 'Esta receita foi calculada para uma travessa de 27x17cm, mas você pode fazer a montagem em qualquer travessa que preferir.', 'Esta receita foi calculada para uma travessa de 27x17cm, mas você pode fazer a montagem em qualquer travessa que preferir.', 8, 1),
      ('fc5257fc-44a5-5da3-9c17-b9a60c93e36a', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'tip', null, 'O creme danete é super versátil, você pode criar outras preparações a partir dele. Esse creme fica maravilhoso para bolo no pote, copos da felicidade, recheio de trufas e tantas outras sobremesas que sua criatividade permitir.', 'O creme danete é super versátil, você pode criar outras preparações a partir dele. Esse creme fica maravilho para bolo no pote, copos da felicidade, recheio de trufas e tantas outras sobremesas que sua criatividade permitir.', 3, 2),
      ('0e365ee1-ba2b-5d6c-aa59-b1a6e1bc1bb0', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'note', 'Marcas usadas pela autora', 'Leite condensado: Itambé · Creme de leite UHT: Itambé · Creme de leite fresco: Fazenda · Bolacha champanhe: Bauducco · Cerejas: Qualitá.', 'Leite condensado - Itambé / Creme de leite uht - Itambé / Creme de leite fresco - Fazenda / Bolacha champanhe - Bauduco / Cerejas - Qualitá', 9, 1),
      ('c53de2db-5b75-563e-aed1-1fd0b0e4ff20', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'note', 'Embalagem', 'Empresa Três Triângulos — Ref.: Travessa Cristal 170x270mm, PA0018.', 'EMPRESA TRÊS TRIÂNGULOS / Ref: Travessa Cristal 170x270mm / PA0018', 10, 2),
      ('c3181479-4b93-580e-bac4-b0f37a605098', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'equipment', null, 'Panela de fundo grosso', null, 5, 1),
      ('82c2db49-41ac-514a-853f-e4681052d1ca', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'equipment', null, 'Vasilha', null, 5, 2),
      ('8d699c4c-ef77-545a-873b-1c8a8e51161b', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'equipment', null, 'Plástico filme', null, 5, 3),
      ('c1073bbb-5771-56a8-b881-6e9dffb421b8', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'equipment', null, 'Batedeira', null, 6, 4),
      ('e93bcf69-0543-5765-8c49-a13d297dd2f8', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'equipment', null, 'Travessa de 27 × 17 cm', null, 8, 5)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('0e5567c8-874c-51ad-bbf3-370b7bcfd17f', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'natal'),
      ('0d2b340e-8516-5e0e-8c78-46af6af2ca55', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'chocolate'),
      ('d431baa1-8018-5d48-88aa-7b07b6cd7874', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'cereja')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('d1d8da16-c252-572e-b4fb-e03660a12881', '480e2ce8-4ca0-5937-901c-dfd4635b091a', null, 'ingredient', '6c07feab-c6cd-52ae-ad7c-084e323d5a49', 'quantity', 'warning', '“1 pacote” — o peso do pacote não é informado no material. O ajuste de porções não converte pacotes automaticamente; valide a quantidade.', 6),
      ('798dec79-0fe2-59e3-a977-7697bda1c696', '480e2ce8-4ca0-5937-901c-dfd4635b091a', null, 'ingredient', 'b49c100c-020a-5cca-ae4a-978c9bf28a7f', 'quantity', 'info', 'Grafia original “cerjas” normalizada para “cerejas”.', 6),
      ('a07234fc-ed7c-5eb2-ab4b-760451d982fb', '480e2ce8-4ca0-5937-901c-dfd4635b091a', null, 'component', '467019ad-814f-521c-8b0b-658df85d2d0e', null, 'info', 'As camadas da página 8 foram rotuladas como “1ª camada … 5ª camada” para o modo cozinheiro. O texto original de cada item está preservado.', 8),
      ('9afa039e-63d0-52f9-9a8e-9ec0198133c5', '480e2ce8-4ca0-5937-901c-dfd4635b091a', null, 'ingredient', 'a2a3eb26-f9bb-5f55-8483-4d1035860f5f', 'quantity', 'warning', 'Quantidade não informada no material (p. 8). Grafia original “granullé” normalizada para “granulé”. Defina “a gosto” ou informe a quantidade após validação.', 8),
      ('b64aeafd-a901-5ee2-b4e6-6a7e2783725e', '480e2ce8-4ca0-5937-901c-dfd4635b091a', null, 'ingredient', 'b7a430f3-9735-5d10-9e30-80791f111691', 'quantity', 'warning', 'Quantidade não informada e o material não traz a receita dos brigadeiros usados na finalização (p. 8).', 8),
      ('48ed79e6-935f-5eee-879e-1338bfa6d263', '480e2ce8-4ca0-5937-901c-dfd4635b091a', null, 'step', 'bbb0f191-231a-50d9-bb7e-f3d64bf2e728', 'instruction', 'info', 'Grafia original “um uma panela” normalizada para “em uma panela”.', 5),
      ('3a2ee376-1e09-5997-9f18-830a736f1cb9', '480e2ce8-4ca0-5937-901c-dfd4635b091a', null, 'timer', 'c879508c-3c60-550f-91c1-216f85535f0d', 'duration_seconds', 'info', 'Tempo mínimo no original (“pelo menos 6h”). O temporizador usa 6 h como referência mínima.', 5),
      ('6cc95256-b8ef-5f3b-be5f-417f84e21ead', '480e2ce8-4ca0-5937-901c-dfd4635b091a', null, 'step', '0f02ffa6-e15a-55ba-a71c-3eb687e34282', 'instruction', 'info', 'Grafia original “áçucar” normalizada para “açúcar”.', 6),
      ('569fe008-42fc-5879-92d6-a390102c6f41', '480e2ce8-4ca0-5937-901c-dfd4635b091a', null, 'note', '0e365ee1-ba2b-5d6c-aa59-b1a6e1bc1bb0', 'body', 'info', 'Grafia original “Bauduco” normalizada para “Bauducco”.', 9),
      ('fa4bb0c8-bac0-5359-9f32-cc871fa9e162', '480e2ce8-4ca0-5937-901c-dfd4635b091a', null, 'recipe', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'servings', 'warning', 'O material informa o rendimento apenas como “uma travessa de 27x17cm”. O número de porções não é informado: a calculadora trabalha por número de travessas até que as porções sejam validadas por um administrador.', 8),
      ('5a1464d9-89ba-5369-8445-eb9e7393527c', '480e2ce8-4ca0-5937-901c-dfd4635b091a', null, 'recipe', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'difficulty', 'info', 'Dificuldade não informada no material. Defina após validação editorial.', null),
      ('16fae445-dcf0-59e1-a2a0-df490271c35d', '480e2ce8-4ca0-5937-901c-dfd4635b091a', null, 'recipe', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'prep_minutes', 'info', 'Tempo total de preparo não informado. O material traz apenas: 4 minutos de fogo após ferver e mínimo de 6 h de geladeira para o creme danete.', 5),
      ('b258d7b2-9eba-56a3-ae06-48a49733f8af', '480e2ce8-4ca0-5937-901c-dfd4635b091a', null, 'recipe', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'source_pages', 'warning', 'O índice do PDF indica: Creme Danete 04, Ingredientes Montagem 05, Montagem 07, Marcas 08, Embalagem 09. As páginas físicas do arquivo são 4–5, 6, 8, 9 e 10. As referências desta ficha usam as páginas físicas.', 2),
      ('7b793656-9a8b-59d5-b6c2-bdbff2c316c7', '480e2ce8-4ca0-5937-901c-dfd4635b091a', null, 'recipe', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'description', 'info', 'Descrição editorial adaptada da introdução da autora (p. 3). O texto original não foi reproduzido integralmente.', 3),
      ('cbbd37cf-af56-5a82-aa46-2ebe7d108882', '480e2ce8-4ca0-5937-901c-dfd4635b091a', null, 'recipe', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'ingredients.leite-condensado', 'info', 'A equivalência caseira original “(1 lata e meia)” é mantida como observação e não é recalculada ao ajustar porções.', 4),
      ('15591e2c-d511-54fd-b201-0f2939037153', '480e2ce8-4ca0-5937-901c-dfd4635b091a', null, 'recipe', '480e2ce8-4ca0-5937-901c-dfd4635b091a', 'ingredients.creme-de-leite', 'info', 'Original: “400g de creme de leite (2 caixinha)”. A página 9 lista a marca como “Creme de leite uht”. Cadastrado separadamente do “creme de leite fresco” para não somar na lista de compras.', 4)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Combinações do montador (a confirmar no PDF)
insert into public.recipe_compatibilities (id, recipe_id, compatible_recipe_id, relation, source_page, verified, note) values
  ('7c871776-012c-5e65-8017-f1b02fce9420', 'a7b40dde-6f46-549e-b241-d1f2ce57b967', '3344a33a-cd35-50c6-b5cc-b4a5a7172aa3', 'recheio', null, false, 'Combinações inferidas dos títulos do material (base doce com recheios doces; base salgada com recheios salgados). Confirmar no PDF, inclusive as finalizações, antes de liberar o montador.'),
  ('ecec4e81-c883-5ec7-ae44-3eba3754fb54', 'a7b40dde-6f46-549e-b241-d1f2ce57b967', 'e046b77b-53ae-553d-a48e-46cc549b2c3f', 'recheio', null, false, 'Combinações inferidas dos títulos do material (base doce com recheios doces; base salgada com recheios salgados). Confirmar no PDF, inclusive as finalizações, antes de liberar o montador.'),
  ('c9b11f48-8d52-5c10-b2d4-bab10b6d288b', 'a7b40dde-6f46-549e-b241-d1f2ce57b967', 'a1727205-c664-5885-8fbf-1b493ab3b56f', 'recheio', null, false, 'Combinações inferidas dos títulos do material (base doce com recheios doces; base salgada com recheios salgados). Confirmar no PDF, inclusive as finalizações, antes de liberar o montador.'),
  ('2e2095c7-fe01-5591-b2ff-34f70193a967', 'd2b5efd4-b9bd-52ae-ad0a-b61c455d5526', '767a747e-c223-5375-901f-ff6252db5054', 'recheio', null, false, 'Combinações inferidas dos títulos do material (base doce com recheios doces; base salgada com recheios salgados). Confirmar no PDF, inclusive as finalizações, antes de liberar o montador.'),
  ('1f59c873-acce-559e-8ae8-35d542a6858c', 'd2b5efd4-b9bd-52ae-ad0a-b61c455d5526', 'd9e29f1e-cf44-5b21-bc7e-7af045cdd5fa', 'recheio', null, false, 'Combinações inferidas dos títulos do material (base doce com recheios doces; base salgada com recheios salgados). Confirmar no PDF, inclusive as finalizações, antes de liberar o montador.'),
  ('f84df9c5-183e-5190-88f4-f6992b9f8468', 'd2b5efd4-b9bd-52ae-ad0a-b61c455d5526', '3a87e780-858a-5e60-9807-636e0e5f38aa', 'recheio', null, false, 'Combinações inferidas dos títulos do material (base doce com recheios doces; base salgada com recheios salgados). Confirmar no PDF, inclusive as finalizações, antes de liberar o montador.')
on conflict (recipe_id, compatible_recipe_id) do nothing;

-- Pontos de revisão de documentos e de itens catalogados
insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
  ('9e47ea54-4bee-52c0-a03d-4bf13bb2f0f2', null, '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'document', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'toc', 'warning', 'Títulos e páginas desta coleção: Sumário informado no MVP — confirmar no PDF. Nenhuma ficha foi estruturada sem o PDF.', null),
  ('d6e5185d-f45e-51cb-ac9d-3d66fa6fdf5e', null, '3a4a09a2-e60d-58ff-bc8f-3bb9217ff12b', 'document', '3a4a09a2-e60d-58ff-bc8f-3bb9217ff12b', 'toc', 'warning', 'Títulos e páginas desta coleção: Índice informado no MVP — confirmar no PDF. Nenhuma ficha foi estruturada sem o PDF.', null),
  ('9c84114a-4184-5c91-97c1-d8e289bb2187', '0d32a443-044d-5b39-bcba-98c64b01f4d5', null, 'recipe', '0d32a443-044d-5b39-bcba-98c64b01f4d5', 'source_page_start', 'info', 'Componente citado no escopo do projeto; página a confirmar no PDF.', null),
  ('0aff65f1-7a64-571a-9473-d1cc8d0b25c8', '55634b07-66b8-577d-a0f3-37e5665ac12a', null, 'recipe', '55634b07-66b8-577d-a0f3-37e5665ac12a', 'source_page_start', 'info', 'Componente citado no escopo do projeto; página a confirmar no PDF.', null),
  ('a15242ba-c0f1-5ece-bb7b-864c28cdb1bf', null, '9f1834ff-9e61-54b7-aaa5-c09bc034f1b0', 'document', '9f1834ff-9e61-54b7-aaa5-c09bc034f1b0', 'toc', 'warning', 'Títulos e páginas desta coleção: Levantamento do MVP — confirmar no PDF. Nenhuma ficha foi estruturada sem o PDF.', null),
  ('a1ef808c-5c8e-5bd2-b980-0d29084be210', null, '9f1834ff-9e61-54b7-aaa5-c09bc034f1b0', 'document', '9f1834ff-9e61-54b7-aaa5-c09bc034f1b0', 'compatibilities', 'warning', 'Combinações inferidas dos títulos do material (base doce com recheios doces; base salgada com recheios salgados). Confirmar no PDF, inclusive as finalizações, antes de liberar o montador.', null),
  ('5a6ec911-f05d-5666-acb0-1555599926a0', null, '48d7904c-48c4-5e7e-9d71-c3f89a3a0026', 'document', '48d7904c-48c4-5e7e-9d71-c3f89a3a0026', 'toc', 'warning', 'Títulos e páginas desta coleção: Índice informado no MVP — confirmar no PDF. Nenhuma ficha foi estruturada sem o PDF.', null)
on conflict (id) do nothing;

commit;
