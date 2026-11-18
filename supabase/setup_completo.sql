-- =====================================================================
-- Clube da Ceia Perfeita — instalação completa do banco (GERADO)
-- Cole este arquivo inteiro no SQL Editor do Supabase de um projeto NOVO e execute uma vez.
-- Conteúdo: 22 migrations + carga inicial (supabase/seed.sql).
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

-- >>>>>>>>>> migrations/20261112000000_simplify_recipe_publication.sql
-- Publicação direta de receitas completas.
-- A liberação não depende mais de aprovação, flags editoriais ou conferência manual.
-- Mantém apenas a proteção para não publicar fichas sem ingredientes e etapas.
create or replace function public.guard_recipe_status()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if new.status = 'published' and new.content_state <> 'structured' then
    raise exception 'CONTENT_REQUIRED: a receita precisa ter ingredientes e modo de preparo cadastrados.' using errcode = 'P0001';
  end if;

  if new.status = 'published' and new.published_at is null then
    new.published_at := now();
  end if;

  return new;
end
$function$;

-- Libera imediatamente as fichas já estruturadas no catálogo.
update public.recipes
set status = 'published',
    published_at = coalesce(published_at, now()),
    updated_at = now()
where content_state = 'structured'
  and kind = 'recipe'
  and status <> 'published'
  and exists (select 1 from public.recipe_ingredients i where i.recipe_id = recipes.id)
  and exists (select 1 from public.recipe_steps s where s.recipe_id = recipes.id);

-- >>>>>>>>>> migrations/20261112150000_support_materials.sql
-- Materiais de apoio compartilhados: utensílios, ingredientes básicos, dicas e orientações.
create table if not exists public.support_materials (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  kind text not null check (kind in ('utensilios', 'ingredientes', 'dicas', 'orientacoes')),
  title text not null,
  body text not null,
  source_document_id uuid references public.source_documents(id) on delete set null,
  source_page integer check (source_page is null or source_page > 0),
  position integer not null default 0,
  is_visible boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists support_materials_kind_position_idx
  on public.support_materials (kind, position);

alter table public.support_materials enable row level security;

grant select, insert, update, delete on public.support_materials to authenticated;

create policy "materiais de apoio para assinantes" on public.support_materials
  for select to authenticated
  using (
    (select public.is_admin())
    or ((select public.has_active_access()) and is_visible)
  );

create policy "administradores gerenciam materiais de apoio" on public.support_materials
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create trigger set_updated_at
  before update on public.support_materials
  for each row execute function public.set_updated_at();

create trigger audit_row_change
  after insert or update or delete on public.support_materials
  for each row execute function public.audit_row_change();

-- >>>>>>>>>> migrations/20261112160000_allow_subscribers_download_source_pdfs.sql
create or replace view public.source_document_refs as
select
  d.id,
  d.title,
  d.author,
  d.publisher,
  d.language,
  d.file_name,
  d.storage_path
from public.source_documents d
where exists (
  select 1
  from public.recipes r
  where r.source_document_id = d.id
    and r.status = 'published'
);

grant select on public.source_document_refs to anon, authenticated;

drop policy if exists "pdfs originais: assinantes e administradores baixam" on storage.objects;
create policy "pdfs originais: assinantes e administradores baixam"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'source-documents'
  and coalesce((select public.my_access() ->> 'has_access'), 'false') = 'true'
);

-- >>>>>>>>>> migrations/20261112180000_automatic_pdf_recipe_import.sql
create or replace function public.admin_import_pdf_recipes(p_document_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_doc public.source_documents%rowtype;
  v_collection_id uuid;
  v_collection_name text;
  v_collection_slug text;
  v_recipe jsonb;
  v_ingredient jsonb;
  v_step jsonb;
  v_material jsonb;
  v_recipe_id uuid;
  v_ingredient_id uuid;
  v_title text;
  v_slug text;
  v_base_slug text;
  v_name text;
  v_name_slug text;
  v_position integer;
  v_ingredient_position integer;
  v_step_position integer;
  v_created integer := 0;
  v_skipped integer := 0;
  v_materials integer := 0;
  v_permission_ok boolean;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'Apenas administradores podem importar documentos.';
  end if;

  select * into v_doc
  from public.source_documents
  where id = p_document_id
  for update;

  if not found then
    raise exception 'Documento não encontrado.';
  end if;

  if v_doc.storage_path is null or v_doc.file_status <> 'stored' then
    raise exception 'Envie o PDF antes de iniciar a leitura.';
  end if;

  if jsonb_typeof(p_payload->'recipes') <> 'array' then
    raise exception 'A leitura não retornou uma lista de receitas válida.';
  end if;

  v_collection_id := v_doc.collection_id;
  v_collection_name := nullif(trim(p_payload#>>'{collection,name}'), '');

  if v_collection_id is null and v_collection_name is not null then
    v_collection_slug := trim(both '-' from regexp_replace(
      lower(translate(v_collection_name,
        'áàâãäéèêëíìîïóòôõöúùûüçñ',
        'aaaaaeeeeiiiiooooouuuucn')),
      '[^a-z0-9]+', '-', 'g'));
    if v_collection_slug = '' then
      v_collection_slug := 'colecao-' || substr(md5(v_collection_name), 1, 8);
    end if;
    insert into public.collections (slug, name, description, experience, position, is_visible)
    values (
      v_collection_slug,
      v_collection_name,
      nullif(trim(p_payload#>>'{collection,description}'), ''),
      'catalog',
      coalesce((select max(position) + 1 from public.collections), 0),
      true
    )
    on conflict (slug) do update set name = excluded.name
    returning id into v_collection_id;

    update public.source_documents
    set collection_id = v_collection_id
    where id = p_document_id;
  end if;

  if v_collection_id is null then
    raise exception 'Não foi possível identificar a categoria deste PDF.';
  end if;

  v_permission_ok := v_doc.commercial_permission = 'confirmed';
  select coalesce(max(position), 0) + 1 into v_position
  from public.recipes
  where collection_id = v_collection_id;

  for v_recipe in
    select value from jsonb_array_elements(p_payload->'recipes')
  loop
    v_title := nullif(trim(v_recipe->>'title'), '');

    if v_title is null
       or jsonb_typeof(v_recipe->'ingredients') <> 'array'
       or jsonb_array_length(v_recipe->'ingredients') = 0
       or jsonb_typeof(v_recipe->'steps') <> 'array'
       or jsonb_array_length(v_recipe->'steps') = 0 then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    if exists (
      select 1 from public.recipes
      where source_document_id = p_document_id
        and lower(title) = lower(v_title)
        and status <> 'archived'
    ) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    v_base_slug := trim(both '-' from regexp_replace(
      lower(translate(v_title,
        'áàâãäéèêëíìîïóòôõöúùûüçñ',
        'aaaaaeeeeiiiiooooouuuucn')),
      '[^a-z0-9]+', '-', 'g'));
    if v_base_slug = '' then
      v_base_slug := 'receita-' || substr(md5(v_title), 1, 8);
    end if;
    v_slug := v_base_slug;
    while exists (select 1 from public.recipes where slug = v_slug) loop
      v_slug := v_base_slug || '-' || substr(md5(v_title || clock_timestamp()::text), 1, 6);
    end loop;

    insert into public.recipes (
      slug, collection_id, source_document_id, kind, title, original_title,
      original_language, translation_status, description, difficulty,
      yield_text, prep_minutes, cook_minutes, bake_minutes, chill_minutes,
      rest_minutes, source_page_start, source_page_end, content_state,
      status, position
    ) values (
      v_slug, v_collection_id, p_document_id, 'recipe', v_title,
      nullif(trim(v_recipe->>'original_title'), ''),
      coalesce(nullif(v_recipe->>'original_language', ''), 'pt-BR'),
      case when coalesce(v_recipe->>'original_language', 'pt-BR') = 'pt-BR' then 'not_needed' else 'pending' end,
      nullif(trim(v_recipe->>'description'), ''),
      case when v_recipe->>'difficulty' in ('facil','media','dificil') then v_recipe->>'difficulty' else null end,
      nullif(trim(v_recipe->>'yield_text'), ''),
      nullif(v_recipe->>'prep_minutes','')::integer,
      nullif(v_recipe->>'cook_minutes','')::integer,
      nullif(v_recipe->>'bake_minutes','')::integer,
      nullif(v_recipe->>'chill_minutes','')::integer,
      nullif(v_recipe->>'rest_minutes','')::integer,
      nullif(v_recipe->>'source_page_start','')::integer,
      nullif(v_recipe->>'source_page_end','')::integer,
      'structured', 'draft', v_position
    ) returning id into v_recipe_id;

    v_ingredient_position := 0;
    for v_ingredient in select value from jsonb_array_elements(v_recipe->'ingredients')
    loop
      v_name := nullif(trim(v_ingredient->>'display_name'), '');
      if v_name is null then
        continue;
      end if;
      v_name_slug := trim(both '-' from regexp_replace(
        lower(translate(v_name,
          'áàâãäéèêëíìîïóòôõöúùûüçñ',
          'aaaaaeeeeiiiiooooouuuucn')),
        '[^a-z0-9]+', '-', 'g'));
      if v_name_slug = '' then
        v_name_slug := 'ingrediente-' || substr(md5(v_name), 1, 8);
      end if;

      insert into public.ingredients (slug, name)
      values (v_name_slug, v_name)
      on conflict (slug) do update set name = excluded.name
      returning id into v_ingredient_id;

      v_ingredient_position := v_ingredient_position + 1;
      insert into public.recipe_ingredients (
        recipe_id, ingredient_id, position, quantity, quantity_max, unit,
        quantity_text, display_name, preparation, scaling, is_optional,
        original_text, source_page, needs_review
      ) values (
        v_recipe_id, v_ingredient_id, v_ingredient_position,
        nullif(v_ingredient->>'quantity','')::numeric,
        nullif(v_ingredient->>'quantity_max','')::numeric,
        nullif(trim(v_ingredient->>'unit'),''),
        nullif(trim(v_ingredient->>'quantity_text'),''),
        v_name,
        nullif(trim(v_ingredient->>'preparation'),''),
        'linear',
        coalesce((v_ingredient->>'is_optional')::boolean, false),
        coalesce(nullif(trim(v_ingredient->>'original_text'), ''), v_name),
        nullif(v_ingredient->>'source_page','')::integer,
        false
      );
    end loop;

    v_step_position := 0;
    for v_step in select value from jsonb_array_elements(v_recipe->'steps')
    loop
      if nullif(trim(v_step->>'instruction'), '') is null then
        continue;
      end if;
      v_step_position := v_step_position + 1;
      insert into public.recipe_steps (
        recipe_id, position, instruction, original_text, tip, source_page, needs_review
      ) values (
        v_recipe_id, v_step_position,
        trim(v_step->>'instruction'),
        nullif(trim(v_step->>'original_text'), ''),
        nullif(trim(v_step->>'tip'), ''),
        nullif(v_step->>'source_page','')::integer,
        false
      );
    end loop;

    if v_ingredient_position = 0 or v_step_position = 0 then
      delete from public.recipes where id = v_recipe_id;
      v_skipped := v_skipped + 1;
      continue;
    end if;

    if v_permission_ok then
      update public.recipes
      set status = 'published', published_at = now()
      where id = v_recipe_id;
    else
      update public.recipes
      set status = 'pending_permission'
      where id = v_recipe_id;
    end if;

    v_created := v_created + 1;
    v_position := v_position + 1;
  end loop;

  for v_material in
    select value from jsonb_array_elements(coalesce(p_payload->'support_materials', '[]'::jsonb))
  loop
    if nullif(trim(v_material->>'title'), '') is null
       or nullif(trim(v_material->>'body'), '') is null then
      continue;
    end if;
    insert into public.support_materials (
      slug, kind, title, body, source_document_id, source_page, position, is_visible
    ) values (
      'pdf-' || substr(md5(p_document_id::text || v_material->>'title' || coalesce(v_material->>'source_page','')),1,20),
      case when v_material->>'kind' in ('utensilios','ingredientes','dicas','orientacoes') then v_material->>'kind' else 'orientacoes' end,
      trim(v_material->>'title'),
      trim(v_material->>'body'),
      p_document_id,
      nullif(v_material->>'source_page','')::integer,
      coalesce((select max(position) + 1 from public.support_materials), 0),
      true
    )
    on conflict (slug) do nothing;
    if found then v_materials := v_materials + 1; end if;
  end loop;

  update public.source_documents
  set import_notes = concat_ws(E'\n', nullif(import_notes, ''),
      'Leitura automática em ' || to_char(now(), 'YYYY-MM-DD HH24:MI') ||
      ': ' || v_created || ' receita(s) criada(s), ' || v_skipped ||
      ' ignorada(s), ' || v_materials || ' material(is) de apoio.')
  where id = p_document_id;

  return jsonb_build_object(
    'created', v_created,
    'skipped', v_skipped,
    'support_materials', v_materials,
    'published', v_permission_ok
  );
end;
$$;

revoke all on function public.admin_import_pdf_recipes(uuid, jsonb) from public, anon;
grant execute on function public.admin_import_pdf_recipes(uuid, jsonb) to authenticated;

-- >>>>>>>>>> migrations/20261112193000_openrouter_secret_from_supabase_vault.sql
create or replace function public.admin_get_openrouter_key()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  secret_value text;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Acesso negado';
  end if;

  select decrypted_secret
    into secret_value
    from vault.decrypted_secrets
   where name = 'openrouter_api_key'
   limit 1;

  return secret_value;
end;
$$;

revoke all on function public.admin_get_openrouter_key() from public;
revoke all on function public.admin_get_openrouter_key() from anon;
grant execute on function public.admin_get_openrouter_key() to authenticated;

-- >>>>>>>>>> migrations/20261112210000_extrair_texto_pdf_sem_ia.sql
create table if not exists public.document_extracted_pages (
  source_document_id uuid not null references public.source_documents(id) on delete cascade,
  page_number integer not null check (page_number > 0),
  page_text text not null default '',
  extracted_at timestamptz not null default now(),
  primary key (source_document_id, page_number)
);

alter table public.document_extracted_pages enable row level security;
revoke all on public.document_extracted_pages from anon, authenticated;
grant select, insert, update, delete on public.document_extracted_pages to authenticated;
grant all on public.document_extracted_pages to service_role;

create policy "administradores acessam texto extraido dos PDFs"
  on public.document_extracted_pages
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

comment on table public.document_extracted_pages is
  'Texto extraído localmente dos PDFs privados para revisão e cadastro administrativo, sem uso de serviços de IA.';

-- >>>>>>>>>> migrations/20261113125253_complete_existing_pdf_recipe_placeholders.sql
CREATE OR REPLACE FUNCTION public.admin_import_pdf_recipes(p_document_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_doc public.source_documents%rowtype;
  v_collection_id uuid;
  v_collection_name text;
  v_collection_slug text;
  v_recipe jsonb;
  v_ingredient jsonb;
  v_step jsonb;
  v_material jsonb;
  v_recipe_id uuid;
  v_ingredient_id uuid;
  v_title text;
  v_slug text;
  v_base_slug text;
  v_name text;
  v_name_slug text;
  v_position integer;
  v_ingredient_position integer;
  v_step_position integer;
  v_created integer := 0;
  v_skipped integer := 0;
  v_materials integer := 0;
  v_permission_ok boolean;
  v_existing_recipe_id uuid;
  v_existing_recipe_empty boolean;
begin
  if not coalesce(public.is_admin(), false) then raise exception 'Apenas administradores podem importar documentos.'; end if;
  select * into v_doc from public.source_documents where id = p_document_id for update;
  if not found then raise exception 'Documento não encontrado.'; end if;
  if v_doc.storage_path is null or v_doc.file_status <> 'stored' then raise exception 'Envie o PDF antes de iniciar a leitura.'; end if;
  if jsonb_typeof(p_payload->'recipes') <> 'array' then raise exception 'A leitura não retornou uma lista de receitas válida.'; end if;

  v_collection_id := v_doc.collection_id;
  v_collection_name := nullif(trim(p_payload#>>'{collection,name}'), '');
  if v_collection_id is null and v_collection_name is not null then
    v_collection_slug := trim(both '-' from regexp_replace(lower(translate(v_collection_name,'áàâãäéèêëíìîïóòôõöúùûüçñ','aaaaaeeeeiiiiooooouuuucn')),'[^a-z0-9]+','-','g'));
    if v_collection_slug = '' then v_collection_slug := 'colecao-' || substr(md5(v_collection_name),1,8); end if;
    insert into public.collections (slug,name,description,experience,position,is_visible)
    values (v_collection_slug,v_collection_name,nullif(trim(p_payload#>>'{collection,description}'),''),'catalog',coalesce((select max(position)+1 from public.collections),0),true)
    on conflict (slug) do update set name=excluded.name returning id into v_collection_id;
    update public.source_documents set collection_id=v_collection_id where id=p_document_id;
  end if;
  if v_collection_id is null then raise exception 'Não foi possível identificar a categoria deste PDF.'; end if;

  v_permission_ok := v_doc.commercial_permission = 'confirmed';
  select coalesce(max(position),0)+1 into v_position from public.recipes where collection_id=v_collection_id;

  for v_recipe in select value from jsonb_array_elements(p_payload->'recipes') loop
    v_title := nullif(trim(v_recipe->>'title'),'');
    if v_title is null or jsonb_typeof(v_recipe->'ingredients') <> 'array' or jsonb_array_length(v_recipe->'ingredients')=0 or jsonb_typeof(v_recipe->'steps') <> 'array' or jsonb_array_length(v_recipe->'steps')=0 then
      v_skipped:=v_skipped+1; continue;
    end if;
    v_existing_recipe_id:=null;
    v_existing_recipe_empty:=false;
    select id into v_existing_recipe_id
      from public.recipes
     where source_document_id=p_document_id
       and lower(title)=lower(v_title)
       and status<>'archived'
     limit 1;

    if v_existing_recipe_id is not null then
      select
        status='draft'
        and content_state='catalogued'
        and not exists(select 1 from public.recipe_ingredients where recipe_id=v_existing_recipe_id)
        and not exists(select 1 from public.recipe_steps where recipe_id=v_existing_recipe_id)
        into v_existing_recipe_empty
        from public.recipes
       where id=v_existing_recipe_id;

      if not coalesce(v_existing_recipe_empty,false) then
        v_skipped:=v_skipped+1;
        continue;
      end if;

      -- Completa a ficha vazia já existente, preservando seu ID, slug e posição.
      v_recipe_id:=v_existing_recipe_id;
      update public.recipes
         set original_title=nullif(trim(v_recipe->>'original_title'),''),
             original_language=coalesce(nullif(v_recipe->>'original_language',''),'pt-BR'),
             translation_status=case when coalesce(v_recipe->>'original_language','pt-BR')='pt-BR' then 'not_needed' else 'pending' end,
             description=nullif(trim(v_recipe->>'description'),''),
             difficulty=case when v_recipe->>'difficulty' in ('facil','media','dificil') then v_recipe->>'difficulty' else null end,
             yield_text=nullif(trim(v_recipe->>'yield_text'),''),
             prep_minutes=nullif(v_recipe->>'prep_minutes','')::integer,
             cook_minutes=nullif(v_recipe->>'cook_minutes','')::integer,
             bake_minutes=nullif(v_recipe->>'bake_minutes','')::integer,
             chill_minutes=nullif(v_recipe->>'chill_minutes','')::integer,
             rest_minutes=nullif(v_recipe->>'rest_minutes','')::integer,
             source_page_start=nullif(v_recipe->>'source_page_start','')::integer,
             source_page_end=nullif(v_recipe->>'source_page_end','')::integer,
             content_state='structured'
       where id=v_recipe_id;
    else
      v_base_slug:=trim(both '-' from regexp_replace(lower(translate(v_title,'áàâãäéèêëíìîïóòôõöúùûüçñ','aaaaaeeeeiiiiooooouuuucn')),'[^a-z0-9]+','-','g'));
      if v_base_slug='' then v_base_slug:='receita-'||substr(md5(v_title),1,8); end if;
      v_slug:=v_base_slug;
      while exists(select 1 from public.recipes where slug=v_slug) loop v_slug:=v_base_slug||'-'||substr(md5(v_title||clock_timestamp()::text),1,6); end loop;

      insert into public.recipes(slug,collection_id,source_document_id,kind,title,original_title,original_language,translation_status,description,difficulty,yield_text,prep_minutes,cook_minutes,bake_minutes,chill_minutes,rest_minutes,source_page_start,source_page_end,content_state,status,position)
      values(v_slug,v_collection_id,p_document_id,'recipe',v_title,nullif(trim(v_recipe->>'original_title'),''),coalesce(nullif(v_recipe->>'original_language',''),'pt-BR'),
        case when coalesce(v_recipe->>'original_language','pt-BR')='pt-BR' then 'not_needed' else 'pending' end,
        nullif(trim(v_recipe->>'description'),''),case when v_recipe->>'difficulty' in ('facil','media','dificil') then v_recipe->>'difficulty' else null end,
        nullif(trim(v_recipe->>'yield_text'),''),nullif(v_recipe->>'prep_minutes','')::integer,nullif(v_recipe->>'cook_minutes','')::integer,
        nullif(v_recipe->>'bake_minutes','')::integer,nullif(v_recipe->>'chill_minutes','')::integer,nullif(v_recipe->>'rest_minutes','')::integer,
        nullif(v_recipe->>'source_page_start','')::integer,nullif(v_recipe->>'source_page_end','')::integer,'structured','draft',v_position)
      returning id into v_recipe_id;
    end if;

    v_ingredient_position:=0;
    for v_ingredient in select value from jsonb_array_elements(v_recipe->'ingredients') loop
      v_name:=nullif(trim(v_ingredient->>'display_name'),'');
      if v_name is null then continue; end if;
      v_name_slug:=trim(both '-' from regexp_replace(lower(translate(v_name,'áàâãäéèêëíìîïóòôõöúùûüçñ','aaaaaeeeeiiiiooooouuuucn')),'[^a-z0-9]+','-','g'));
      if v_name_slug='' then v_name_slug:='ingrediente-'||substr(md5(v_name),1,8); end if;
      insert into public.ingredients(slug,name) values(v_name_slug,v_name)
      on conflict(slug) do update set name=excluded.name returning id into v_ingredient_id;
      v_ingredient_position:=v_ingredient_position+1;
      insert into public.recipe_ingredients(recipe_id,ingredient_id,position,quantity,quantity_max,unit,quantity_text,display_name,preparation,scaling,is_optional,original_text,source_page,needs_review)
      values(v_recipe_id,v_ingredient_id,v_ingredient_position,nullif(v_ingredient->>'quantity','')::numeric,nullif(v_ingredient->>'quantity_max','')::numeric,
        nullif(trim(v_ingredient->>'unit'),''),nullif(trim(v_ingredient->>'quantity_text'),''),v_name,nullif(trim(v_ingredient->>'preparation'),''),'linear',
        coalesce((v_ingredient->>'is_optional')::boolean,false),coalesce(nullif(trim(v_ingredient->>'original_text'),''),v_name),nullif(v_ingredient->>'source_page','')::integer,false);
    end loop;

    v_step_position:=0;
    for v_step in select value from jsonb_array_elements(v_recipe->'steps') loop
      if nullif(trim(v_step->>'instruction'),'') is null then continue; end if;
      v_step_position:=v_step_position+1;
      insert into public.recipe_steps(recipe_id,position,instruction,original_text,tip,source_page,needs_review)
      values(v_recipe_id,v_step_position,trim(v_step->>'instruction'),nullif(trim(v_step->>'original_text'),''),nullif(trim(v_step->>'tip'),''),nullif(v_step->>'source_page','')::integer,false);
    end loop;

    if v_ingredient_position=0 or v_step_position=0 then delete from public.recipes where id=v_recipe_id; v_skipped:=v_skipped+1; continue; end if;
    if v_permission_ok then update public.recipes set status='published',published_at=now() where id=v_recipe_id;
    else update public.recipes set status='pending_permission' where id=v_recipe_id; end if;
    v_created:=v_created+1; v_position:=v_position+1;
  end loop;

  for v_material in select value from jsonb_array_elements(coalesce(p_payload->'support_materials','[]'::jsonb)) loop
    if nullif(trim(v_material->>'title'),'') is null or nullif(trim(v_material->>'body'),'') is null then continue; end if;
    insert into public.support_materials(slug,kind,title,body,source_document_id,source_page,position,is_visible)
    values('pdf-'||substr(md5(p_document_id::text||v_material->>'title'||coalesce(v_material->>'source_page','')),1,20),
      case when v_material->>'kind' in ('utensilios','ingredientes','dicas','orientacoes') then v_material->>'kind' else 'orientacoes' end,
      trim(v_material->>'title'),trim(v_material->>'body'),p_document_id,nullif(v_material->>'source_page','')::integer,
      coalesce((select max(position)+1 from public.support_materials),0),true)
    on conflict(slug) do nothing;
    if found then v_materials:=v_materials+1; end if;
  end loop;

  update public.source_documents set import_notes=concat_ws(E'\n',nullif(import_notes,''),'Leitura automática em '||to_char(now(),'YYYY-MM-DD HH24:MI')||': '||v_created||' receita(s) criada(s), '||v_skipped||' ignorada(s), '||v_materials||' material(is) de apoio.') where id=p_document_id;
  return jsonb_build_object('created',v_created,'skipped',v_skipped,'support_materials',v_materials,'published',v_permission_ok);
end;
$function$

-- >>>>>>>>>> migrations/20261114011648_fix_support_materials_slug_expression.sql
-- Corrige a precedência dos operadores ao gerar o slug de materiais de apoio.
-- Sem os parênteses, o PostgreSQL tentava aplicar ->> ao resultado de concatenação.
CREATE OR REPLACE FUNCTION public.admin_import_pdf_recipes(p_document_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_doc public.source_documents%rowtype;
  v_collection_id uuid;
  v_collection_name text;
  v_collection_slug text;
  v_recipe jsonb;
  v_ingredient jsonb;
  v_step jsonb;
  v_material jsonb;
  v_recipe_id uuid;
  v_ingredient_id uuid;
  v_title text;
  v_slug text;
  v_base_slug text;
  v_name text;
  v_name_slug text;
  v_position integer;
  v_ingredient_position integer;
  v_step_position integer;
  v_created integer := 0;
  v_skipped integer := 0;
  v_materials integer := 0;
  v_permission_ok boolean;
  v_existing_recipe_id uuid;
  v_existing_recipe_empty boolean;
begin
  if not coalesce(public.is_admin(), false) then raise exception 'Apenas administradores podem importar documentos.'; end if;
  select * into v_doc from public.source_documents where id = p_document_id for update;
  if not found then raise exception 'Documento não encontrado.'; end if;
  if v_doc.storage_path is null or v_doc.file_status <> 'stored' then raise exception 'Envie o PDF antes de iniciar a leitura.'; end if;
  if jsonb_typeof(p_payload->'recipes') <> 'array' then raise exception 'A leitura não retornou uma lista de receitas válida.'; end if;

  v_collection_id := v_doc.collection_id;
  v_collection_name := nullif(trim(p_payload#>>'{collection,name}'), '');
  if v_collection_id is null and v_collection_name is not null then
    v_collection_slug := trim(both '-' from regexp_replace(lower(translate(v_collection_name,'áàâãäéèêëíìîïóòôõöúùûüçñ','aaaaaeeeeiiiiooooouuuucn')),'[^a-z0-9]+','-','g'));
    if v_collection_slug = '' then v_collection_slug := 'colecao-' || substr(md5(v_collection_name),1,8); end if;
    insert into public.collections (slug,name,description,experience,position,is_visible)
    values (v_collection_slug,v_collection_name,nullif(trim(p_payload#>>'{collection,description}'),''),'catalog',coalesce((select max(position)+1 from public.collections),0),true)
    on conflict (slug) do update set name=excluded.name returning id into v_collection_id;
    update public.source_documents set collection_id=v_collection_id where id=p_document_id;
  end if;
  if v_collection_id is null then raise exception 'Não foi possível identificar a categoria deste PDF.'; end if;

  v_permission_ok := v_doc.commercial_permission = 'confirmed';
  select coalesce(max(position),0)+1 into v_position from public.recipes where collection_id=v_collection_id;

  for v_recipe in select value from jsonb_array_elements(p_payload->'recipes') loop
    v_title := nullif(trim(v_recipe->>'title'),'');
    if v_title is null or jsonb_typeof(v_recipe->'ingredients') <> 'array' or jsonb_array_length(v_recipe->'ingredients')=0 or jsonb_typeof(v_recipe->'steps') <> 'array' or jsonb_array_length(v_recipe->'steps')=0 then
      v_skipped:=v_skipped+1; continue;
    end if;
    v_existing_recipe_id:=null;
    v_existing_recipe_empty:=false;
    select id into v_existing_recipe_id
      from public.recipes
     where source_document_id=p_document_id
       and lower(title)=lower(v_title)
       and status<>'archived'
     limit 1;

    if v_existing_recipe_id is not null then
      select
        status='draft'
        and content_state='catalogued'
        and not exists(select 1 from public.recipe_ingredients where recipe_id=v_existing_recipe_id)
        and not exists(select 1 from public.recipe_steps where recipe_id=v_existing_recipe_id)
        into v_existing_recipe_empty
        from public.recipes
       where id=v_existing_recipe_id;

      if not coalesce(v_existing_recipe_empty,false) then
        v_skipped:=v_skipped+1;
        continue;
      end if;

      -- Completa a ficha vazia já existente, preservando seu ID, slug e posição.
      v_recipe_id:=v_existing_recipe_id;
      update public.recipes
         set original_title=nullif(trim(v_recipe->>'original_title'),''),
             original_language=coalesce(nullif(v_recipe->>'original_language',''),'pt-BR'),
             translation_status=case when coalesce(v_recipe->>'original_language','pt-BR')='pt-BR' then 'not_needed' else 'pending' end,
             description=nullif(trim(v_recipe->>'description'),''),
             difficulty=case when v_recipe->>'difficulty' in ('facil','media','dificil') then v_recipe->>'difficulty' else null end,
             yield_text=nullif(trim(v_recipe->>'yield_text'),''),
             prep_minutes=nullif(v_recipe->>'prep_minutes','')::integer,
             cook_minutes=nullif(v_recipe->>'cook_minutes','')::integer,
             bake_minutes=nullif(v_recipe->>'bake_minutes','')::integer,
             chill_minutes=nullif(v_recipe->>'chill_minutes','')::integer,
             rest_minutes=nullif(v_recipe->>'rest_minutes','')::integer,
             source_page_start=nullif(v_recipe->>'source_page_start','')::integer,
             source_page_end=nullif(v_recipe->>'source_page_end','')::integer,
             content_state='structured'
       where id=v_recipe_id;
    else
      v_base_slug:=trim(both '-' from regexp_replace(lower(translate(v_title,'áàâãäéèêëíìîïóòôõöúùûüçñ','aaaaaeeeeiiiiooooouuuucn')),'[^a-z0-9]+','-','g'));
      if v_base_slug='' then v_base_slug:='receita-'||substr(md5(v_title),1,8); end if;
      v_slug:=v_base_slug;
      while exists(select 1 from public.recipes where slug=v_slug) loop v_slug:=v_base_slug||'-'||substr(md5(v_title||clock_timestamp()::text),1,6); end loop;

      insert into public.recipes(slug,collection_id,source_document_id,kind,title,original_title,original_language,translation_status,description,difficulty,yield_text,prep_minutes,cook_minutes,bake_minutes,chill_minutes,rest_minutes,source_page_start,source_page_end,content_state,status,position)
      values(v_slug,v_collection_id,p_document_id,'recipe',v_title,nullif(trim(v_recipe->>'original_title'),''),coalesce(nullif(v_recipe->>'original_language',''),'pt-BR'),
        case when coalesce(v_recipe->>'original_language','pt-BR')='pt-BR' then 'not_needed' else 'pending' end,
        nullif(trim(v_recipe->>'description'),''),case when v_recipe->>'difficulty' in ('facil','media','dificil') then v_recipe->>'difficulty' else null end,
        nullif(trim(v_recipe->>'yield_text'),''),nullif(v_recipe->>'prep_minutes','')::integer,nullif(v_recipe->>'cook_minutes','')::integer,
        nullif(v_recipe->>'bake_minutes','')::integer,nullif(v_recipe->>'chill_minutes','')::integer,nullif(v_recipe->>'rest_minutes','')::integer,
        nullif(v_recipe->>'source_page_start','')::integer,nullif(v_recipe->>'source_page_end','')::integer,'structured','draft',v_position)
      returning id into v_recipe_id;
    end if;

    v_ingredient_position:=0;
    for v_ingredient in select value from jsonb_array_elements(v_recipe->'ingredients') loop
      v_name:=nullif(trim(v_ingredient->>'display_name'),'');
      if v_name is null then continue; end if;
      v_name_slug:=trim(both '-' from regexp_replace(lower(translate(v_name,'áàâãäéèêëíìîïóòôõöúùûüçñ','aaaaaeeeeiiiiooooouuuucn')),'[^a-z0-9]+','-','g'));
      if v_name_slug='' then v_name_slug:='ingrediente-'||substr(md5(v_name),1,8); end if;
      insert into public.ingredients(slug,name) values(v_name_slug,v_name)
      on conflict(slug) do update set name=excluded.name returning id into v_ingredient_id;
      v_ingredient_position:=v_ingredient_position+1;
      insert into public.recipe_ingredients(recipe_id,ingredient_id,position,quantity,quantity_max,unit,quantity_text,display_name,preparation,scaling,is_optional,original_text,source_page,needs_review)
      values(v_recipe_id,v_ingredient_id,v_ingredient_position,nullif(v_ingredient->>'quantity','')::numeric,nullif(v_ingredient->>'quantity_max','')::numeric,
        nullif(trim(v_ingredient->>'unit'),''),nullif(trim(v_ingredient->>'quantity_text'),''),v_name,nullif(trim(v_ingredient->>'preparation'),''),'linear',
        coalesce((v_ingredient->>'is_optional')::boolean,false),coalesce(nullif(trim(v_ingredient->>'original_text'),''),v_name),nullif(v_ingredient->>'source_page','')::integer,false);
    end loop;

    v_step_position:=0;
    for v_step in select value from jsonb_array_elements(v_recipe->'steps') loop
      if nullif(trim(v_step->>'instruction'),'') is null then continue; end if;
      v_step_position:=v_step_position+1;
      insert into public.recipe_steps(recipe_id,position,instruction,original_text,tip,source_page,needs_review)
      values(v_recipe_id,v_step_position,trim(v_step->>'instruction'),nullif(trim(v_step->>'original_text'),''),nullif(trim(v_step->>'tip'),''),nullif(v_step->>'source_page','')::integer,false);
    end loop;

    if v_ingredient_position=0 or v_step_position=0 then delete from public.recipes where id=v_recipe_id; v_skipped:=v_skipped+1; continue; end if;
    if v_permission_ok then update public.recipes set status='published',published_at=now() where id=v_recipe_id;
    else update public.recipes set status='pending_permission' where id=v_recipe_id; end if;
    v_created:=v_created+1; v_position:=v_position+1;
  end loop;

  for v_material in select value from jsonb_array_elements(coalesce(p_payload->'support_materials','[]'::jsonb)) loop
    if nullif(trim(v_material->>'title'),'') is null or nullif(trim(v_material->>'body'),'') is null then continue; end if;
    insert into public.support_materials(slug,kind,title,body,source_document_id,source_page,position,is_visible)
    values('pdf-'||substr(md5(p_document_id::text || (v_material->>'title') || coalesce(v_material->>'source_page','')),1,20),
      case when v_material->>'kind' in ('utensilios','ingredientes','dicas','orientacoes') then v_material->>'kind' else 'orientacoes' end,
      trim(v_material->>'title'),trim(v_material->>'body'),p_document_id,nullif(v_material->>'source_page','')::integer,
      coalesce((select max(position)+1 from public.support_materials),0),true)
    on conflict(slug) do nothing;
    if found then v_materials:=v_materials+1; end if;
  end loop;

  update public.source_documents set import_notes=concat_ws(E'\n',nullif(import_notes,''),'Leitura automática em '||to_char(now(),'YYYY-MM-DD HH24:MI')||': '||v_created||' receita(s) criada(s), '||v_skipped||' ignorada(s), '||v_materials||' material(is) de apoio.') where id=p_document_id;
  return jsonb_build_object('created',v_created,'skipped',v_skipped,'support_materials',v_materials,'published',v_permission_ok);
end;
$function$

-- >>>>>>>>>> migrations/20261114020000_structure_torta_de_chocolate.sql
-- Registra a estruturação inicial da Torta de Chocolate.
-- A receita já foi estruturada diretamente no banco; esta migração é idempotente
-- para manter o mesmo estado em ambientes que ainda não receberam os dados.
with target as (
  select id
  from public.recipes
  where slug = 'torta-de-chocolate'
    and source_page_start = 5
    and source_page_end = 5
),
components_to_create(role, title, position) as (
  values
    ('massa'::text, 'Massa'::text, 1),
    ('recheio'::text, 'Recheio'::text, 2),
    ('cobertura'::text, 'Cobertura'::text, 3)
),
inserted as (
  insert into public.recipe_components
    (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
  select target.id, spec.role, spec.title, 1, spec.position, 5, 5
  from target
  cross join components_to_create spec
  where not exists (
    select 1
    from public.recipe_components existing
    where existing.recipe_id = target.id
      and existing.position = spec.position
  )
  returning id
)
update public.recipe_ingredients ingredient
set component_id = component.id,
    updated_at = now()
from target,
     public.recipe_components component
where ingredient.recipe_id = target.id
  and component.recipe_id = target.id
  and ingredient.component_id is null
  and (
    (component.role = 'massa' and ingredient.position between 1 and 2)
    or (component.role = 'recheio' and ingredient.position between 3 and 5)
    or (component.role = 'cobertura' and ingredient.position between 6 and 7)
  );

with target as (
  select id
  from public.recipes
  where slug = 'torta-de-chocolate'
    and source_page_start = 5
    and source_page_end = 5
)
update public.recipe_steps step
set component_id = component.id,
    updated_at = now()
from target,
     public.recipe_components component
where step.recipe_id = target.id
  and component.recipe_id = target.id
  and step.component_id is null
  and (
    (component.role = 'massa' and step.position = 1)
    or (component.role = 'recheio' and step.position between 2 and 3)
    or (component.role = 'cobertura' and step.position = 4)
  );

-- >>>>>>>>>> migrations/20261114021500_structure_tortas_components.sql
-- Estrutura componentes de nove tortas com grupos e instruções explícitos nas páginas de origem.
-- Idempotente: cria componentes ausentes e só associa registros ainda sem componente.
begin;

insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 6, 6
from public.recipes rec
where rec.slug='torta-de-banana-e-coco' and rec.source_page_start=6
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=1
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-banana-e-coco' and rec.source_page_start=6
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 3;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-banana-e-coco' and rec.source_page_start=6
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1,2,3);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Recheio', 1, 2, 6, 6
from public.recipes rec
where rec.slug='torta-de-banana-e-coco' and rec.source_page_start=6
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=2
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-banana-e-coco' and rec.source_page_start=6
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 4 and 8;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-banana-e-coco' and rec.source_page_start=6
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (4,5);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura', 1, 3, 6, 6
from public.recipes rec
where rec.slug='torta-de-banana-e-coco' and rec.source_page_start=6
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=3
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-banana-e-coco' and rec.source_page_start=6
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura'
  and ri.position between 9 and 9;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-banana-e-coco' and rec.source_page_start=6
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura'
  and rs.position in (6);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 7, 7
from public.recipes rec
where rec.slug='torta-de-chantilly-com-maracuja' and rec.source_page_start=7
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=1
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-chantilly-com-maracuja' and rec.source_page_start=7
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 2;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-chantilly-com-maracuja' and rec.source_page_start=7
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme', 1, 2, 7, 7
from public.recipes rec
where rec.slug='torta-de-chantilly-com-maracuja' and rec.source_page_start=7
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=2
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-chantilly-com-maracuja' and rec.source_page_start=7
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme'
  and ri.position between 3 and 9;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-chantilly-com-maracuja' and rec.source_page_start=7
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme'
  and rs.position in (2,3,4);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura', 1, 3, 7, 7
from public.recipes rec
where rec.slug='torta-de-chantilly-com-maracuja' and rec.source_page_start=7
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=3
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-chantilly-com-maracuja' and rec.source_page_start=7
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura'
  and ri.position between 10 and 13;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-chantilly-com-maracuja' and rec.source_page_start=7
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura'
  and rs.position in (5,6);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 8, 8
from public.recipes rec
where rec.slug='torta-de-ameixa-com-nozes' and rec.source_page_start=8
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=1
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-ameixa-com-nozes' and rec.source_page_start=8
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 5;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-ameixa-com-nozes' and rec.source_page_start=8
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1,2,3,6);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Recheio', 1, 2, 8, 8
from public.recipes rec
where rec.slug='torta-de-ameixa-com-nozes' and rec.source_page_start=8
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=2
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-ameixa-com-nozes' and rec.source_page_start=8
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 6 and 8;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-ameixa-com-nozes' and rec.source_page_start=8
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (4,5);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura', 1, 3, 8, 8
from public.recipes rec
where rec.slug='torta-de-ameixa-com-nozes' and rec.source_page_start=8
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=3
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-ameixa-com-nozes' and rec.source_page_start=8
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura'
  and ri.position between 9 and 10;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-ameixa-com-nozes' and rec.source_page_start=8
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura'
  and rs.position in (7);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 10, 10
from public.recipes rec
where rec.slug='torta-doce-de-milho' and rec.source_page_start=10
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=1
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-doce-de-milho' and rec.source_page_start=10
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 2;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-doce-de-milho' and rec.source_page_start=10
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1,2);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Recheio', 1, 2, 10, 10
from public.recipes rec
where rec.slug='torta-doce-de-milho' and rec.source_page_start=10
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=2
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-doce-de-milho' and rec.source_page_start=10
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 3 and 7;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-doce-de-milho' and rec.source_page_start=10
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (3,4,5);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 12, 12
from public.recipes rec
where rec.slug='torta-mousse-de-mel' and rec.source_page_start=12
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=1
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-mousse-de-mel' and rec.source_page_start=12
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 2;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-mousse-de-mel' and rec.source_page_start=12
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Mousse de mel', 1, 2, 12, 12
from public.recipes rec
where rec.slug='torta-mousse-de-mel' and rec.source_page_start=12
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=2
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-mousse-de-mel' and rec.source_page_start=12
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 3 and 8;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-mousse-de-mel' and rec.source_page_start=12
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (2,3);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 13, 13
from public.recipes rec
where rec.slug='torta-de-manga' and rec.source_page_start=13
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=1
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-manga' and rec.source_page_start=13
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 2;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-manga' and rec.source_page_start=13
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Recheio de manga', 1, 2, 13, 13
from public.recipes rec
where rec.slug='torta-de-manga' and rec.source_page_start=13
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=2
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-manga' and rec.source_page_start=13
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 3 and 8;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-manga' and rec.source_page_start=13
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (2,3,4,5);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 14, 14
from public.recipes rec
where rec.slug='torta-romeu-e-julieta' and rec.source_page_start=14
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=1
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-romeu-e-julieta' and rec.source_page_start=14
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 2;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-romeu-e-julieta' and rec.source_page_start=14
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Recheio', 1, 2, 14, 14
from public.recipes rec
where rec.slug='torta-romeu-e-julieta' and rec.source_page_start=14
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=2
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-romeu-e-julieta' and rec.source_page_start=14
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 3 and 7;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-romeu-e-julieta' and rec.source_page_start=14
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (2,3);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura de goiabada', 1, 3, 14, 14
from public.recipes rec
where rec.slug='torta-romeu-e-julieta' and rec.source_page_start=14
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=3
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-romeu-e-julieta' and rec.source_page_start=14
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura'
  and ri.position between 8 and 8;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-romeu-e-julieta' and rec.source_page_start=14
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura'
  and rs.position in (4);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 15, 15
from public.recipes rec
where rec.slug='torta-de-nozes' and rec.source_page_start=15
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=1
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-nozes' and rec.source_page_start=15
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 2;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-nozes' and rec.source_page_start=15
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1,2);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Recheio de nozes', 1, 2, 15, 15
from public.recipes rec
where rec.slug='torta-de-nozes' and rec.source_page_start=15
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=2
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-nozes' and rec.source_page_start=15
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 3 and 8;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-nozes' and rec.source_page_start=15
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (3,4);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura de chantilly', 1, 3, 15, 15
from public.recipes rec
where rec.slug='torta-de-nozes' and rec.source_page_start=15
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=3
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-nozes' and rec.source_page_start=15
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura'
  and ri.position between 9 and 9;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-nozes' and rec.source_page_start=15
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura'
  and rs.position in (5);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 18, 18
from public.recipes rec
where rec.slug='torta-sorvete-de-cafe' and rec.source_page_start=18
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=1
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-sorvete-de-cafe' and rec.source_page_start=18
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 2;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-sorvete-de-cafe' and rec.source_page_start=18
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1,2);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Recheio de sorvete e café', 1, 2, 18, 18
from public.recipes rec
where rec.slug='torta-sorvete-de-cafe' and rec.source_page_start=18
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=2
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-sorvete-de-cafe' and rec.source_page_start=18
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 3 and 4;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-sorvete-de-cafe' and rec.source_page_start=18
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (3,4);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura', 1, 3, 18, 18
from public.recipes rec
where rec.slug='torta-sorvete-de-cafe' and rec.source_page_start=18
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=3
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-sorvete-de-cafe' and rec.source_page_start=18
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura'
  and ri.position between 5 and 5;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-sorvete-de-cafe' and rec.source_page_start=18
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura'
  and rs.position in (5);

commit;

-- >>>>>>>>>> migrations/20261114032000_structure_remaining_tortas.sql
-- Completa a estrutura das tortas restantes com grupos sustentados pelas listas e instruções da apostila.
-- Torta de Pêra permanece sem divisão: as instruções intercalam massa, recheio e montagem,
-- e a visualização atual agrupa etapas por componente, o que alteraria a ordem original.
begin;

insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 9, 9
from public.recipes rec
where rec.slug='torta-de-limao' and rec.source_page_start=9
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-limao' and rec.source_page_start=9
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 5;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-limao' and rec.source_page_start=9
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1,2,3);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Recheio', 1, 2, 9, 9
from public.recipes rec
where rec.slug='torta-de-limao' and rec.source_page_start=9
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-limao' and rec.source_page_start=9
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 6 and 9;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-limao' and rec.source_page_start=9
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (4);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura', 1, 3, 9, 9
from public.recipes rec
where rec.slug='torta-de-limao' and rec.source_page_start=9
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-limao' and rec.source_page_start=9
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura'
  and ri.position between 10 and 12;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-limao' and rec.source_page_start=9
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura'
  and rs.position in (5,6,7);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme', 1, 1, 11, 11
from public.recipes rec
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme'
  and ri.position between 1 and 5;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme'
  and rs.position in (1,2,3);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem', 1, 2, 11, 11
from public.recipes rec
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem'
  and ri.position between 6 and 6;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem'
  and rs.position in (4,5,6);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura de chocolate', 1, 3, 11, 11
from public.recipes rec
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura'
  and ri.position between 7 and 9;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura'
  and rs.position in (7,8);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Finalização', 1, 4, 11, 11
from public.recipes rec
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=4);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='finalizacao'
  and ri.position between 10 and 10;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao'
  and rs.position in (9);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 16, 16
from public.recipes rec
where rec.slug='torta-integral' and rec.source_page_start=16
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-integral' and rec.source_page_start=16
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 6;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-integral' and rec.source_page_start=16
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Recheio', 1, 2, 16, 16
from public.recipes rec
where rec.slug='torta-integral' and rec.source_page_start=16
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-integral' and rec.source_page_start=16
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 7 and 11;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-integral' and rec.source_page_start=16
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (2);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem', 1, 3, 16, 16
from public.recipes rec
where rec.slug='torta-integral' and rec.source_page_start=16
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);



update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-integral' and rec.source_page_start=16
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem'
  and rs.position in (3);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Recheio', 1, 1, 19, 19
from public.recipes rec
where rec.slug='torta-de-maca' and rec.source_page_start=19
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-maca' and rec.source_page_start=19
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 10 and 14;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-maca' and rec.source_page_start=19
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (1);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 2, 19, 19
from public.recipes rec
where rec.slug='torta-de-maca' and rec.source_page_start=19
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-maca' and rec.source_page_start=19
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 6;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-maca' and rec.source_page_start=19
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (2,3);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura', 1, 3, 19, 19
from public.recipes rec
where rec.slug='torta-de-maca' and rec.source_page_start=19
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-maca' and rec.source_page_start=19
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura'
  and ri.position between 7 and 9;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-maca' and rec.source_page_start=19
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura'
  and rs.position in (4,5);

commit;

-- >>>>>>>>>> migrations/20261114033500_structure_torta_de_pera.sql
-- Estrutura a Torta de Pêra sem alterar a sequência do preparo.
-- As etapas intercaladas são separadas em partes sequenciais: massa, recheio,
-- montagem e finalização. Os ingredientes são mantidos em suas listas originais.
begin;

insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select r.id, v.role, v.title, 1, v.position, 17, 17
from public.recipes r
cross join (values
  ('massa'::text,'Massa'::text,1),
  ('recheio'::text,'Recheio de pera'::text,2),
  ('montagem'::text,'Montagem'::text,3),
  ('finalizacao'::text,'Finalização'::text,4)
) v(role,title,position)
where r.slug='torta-de-pera' and r.source_page_start=17
  and not exists (
    select 1 from public.recipe_components rc
    where rc.recipe_id=r.id and rc.position=v.position
  );

update public.recipe_ingredients i
set component_id=rc.id, updated_at=now()
from public.recipes r
join public.recipe_components rc on rc.recipe_id=r.id
where r.slug='torta-de-pera' and r.source_page_start=17
  and i.recipe_id=r.id and i.component_id is null
  and (
    (rc.role='massa' and i.position between 1 and 5)
    or (rc.role='finalizacao' and i.position between 6 and 8)
    or (rc.role='recheio' and i.position between 9 and 15)
  );

update public.recipe_steps s
set component_id=rc.id, updated_at=now()
from public.recipes r
join public.recipe_components rc on rc.recipe_id=r.id
where r.slug='torta-de-pera' and r.source_page_start=17
  and s.recipe_id=r.id and s.component_id is null
  and (
    (rc.role='massa' and s.position=1)
    or (rc.role='recheio' and s.position in (2,3))
    or (rc.role='montagem' and s.position in (4,5))
    or (rc.role='finalizacao' and s.position=6)
  );

commit;

-- >>>>>>>>>> migrations/20261114040000_structure_pudins_components.sql
-- Estrutura as 13 fichas de pudins com caldas, massas, ganaches, coberturas e etapas na ordem da apostila.
-- As caldas/coberturas citadas em materiais de apoio permanecem também na biblioteca de apoio.
begin;

insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa do pudim', 1, 1, 12, 12
from public.recipes rec
where rec.slug='pudim-tradicional' and rec.source_page_start=12
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-tradicional' and rec.source_page_start=12
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-tradicional' and rec.source_page_start=12
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'calda', 'Calda e montagem', 1, 2, 12, 12
from public.recipes rec
where rec.slug='pudim-tradicional' and rec.source_page_start=12
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-tradicional' and rec.source_page_start=12
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='calda' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-tradicional' and rec.source_page_start=12
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='calda' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e finalização', 1, 3, 12, 12
from public.recipes rec
where rec.slug='pudim-tradicional' and rec.source_page_start=12
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-tradicional' and rec.source_page_start=12
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[5,6]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa do pudim de café', 1, 1, 13, 13
from public.recipes rec
where rec.slug='pudim-de-cafe' and rec.source_page_start=13
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-cafe' and rec.source_page_start=13
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-cafe' and rec.source_page_start=13
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'calda', 'Calda e montagem', 1, 2, 13, 13
from public.recipes rec
where rec.slug='pudim-de-cafe' and rec.source_page_start=13
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-cafe' and rec.source_page_start=13
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='calda' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-cafe' and rec.source_page_start=13
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='calda' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e finalização', 1, 3, 13, 13
from public.recipes rec
where rec.slug='pudim-de-cafe' and rec.source_page_start=13
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-cafe' and rec.source_page_start=13
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[5,6,7]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa de chocolate', 1, 1, 14, 14
from public.recipes rec
where rec.slug='pudim-de-chocolate-meio-amargo' and rec.source_page_start=14
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-meio-amargo' and rec.source_page_start=14
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5,6,7]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-meio-amargo' and rec.source_page_start=14
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'calda', 'Calda de chocolate e montagem', 1, 2, 14, 14
from public.recipes rec
where rec.slug='pudim-de-chocolate-meio-amargo' and rec.source_page_start=14
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-meio-amargo' and rec.source_page_start=14
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='calda' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-meio-amargo' and rec.source_page_start=14
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='calda' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e finalização', 1, 3, 14, 14
from public.recipes rec
where rec.slug='pudim-de-chocolate-meio-amargo' and rec.source_page_start=14
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-meio-amargo' and rec.source_page_start=14
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[5,6,7]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa de coco', 1, 1, 15, 15
from public.recipes rec
where rec.slug='pudim-de-coco' and rec.source_page_start=15
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-coco' and rec.source_page_start=15
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-coco' and rec.source_page_start=15
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'calda', 'Calda e montagem', 1, 2, 15, 15
from public.recipes rec
where rec.slug='pudim-de-coco' and rec.source_page_start=15
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-coco' and rec.source_page_start=15
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='calda' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-coco' and rec.source_page_start=15
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='calda' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e finalização', 1, 3, 15, 15
from public.recipes rec
where rec.slug='pudim-de-coco' and rec.source_page_start=15
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-coco' and rec.source_page_start=15
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[5,6]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa de doce de leite', 1, 1, 16, 16
from public.recipes rec
where rec.slug='pudim-de-doce-de-leite' and rec.source_page_start=16
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-doce-de-leite' and rec.source_page_start=16
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-doce-de-leite' and rec.source_page_start=16
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'calda', 'Calda e montagem', 1, 2, 16, 16
from public.recipes rec
where rec.slug='pudim-de-doce-de-leite' and rec.source_page_start=16
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-doce-de-leite' and rec.source_page_start=16
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='calda' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-doce-de-leite' and rec.source_page_start=16
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='calda' and rs.position = any(array[3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e finalização', 1, 3, 16, 16
from public.recipes rec
where rec.slug='pudim-de-doce-de-leite' and rec.source_page_start=16
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-doce-de-leite' and rec.source_page_start=16
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[4,5]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa de pistache', 1, 1, 17, 17
from public.recipes rec
where rec.slug='pudim-de-pistache' and rec.source_page_start=17
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-pistache' and rec.source_page_start=17
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-pistache' and rec.source_page_start=17
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'calda', 'Calda e montagem', 1, 2, 17, 17
from public.recipes rec
where rec.slug='pudim-de-pistache' and rec.source_page_start=17
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-pistache' and rec.source_page_start=17
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='calda' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-pistache' and rec.source_page_start=17
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='calda' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e finalização', 1, 3, 17, 17
from public.recipes rec
where rec.slug='pudim-de-pistache' and rec.source_page_start=17
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-pistache' and rec.source_page_start=17
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[5,6]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'base', 'Preparação da forma', 1, 1, 18, 18
from public.recipes rec
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='base' and ri.position = any(array[8]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='base' and rs.position = any(array[1]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Ganache de chocolate branco', 1, 2, 18, 18
from public.recipes rec
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[3,7]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa do pudim', 1, 3, 18, 18
from public.recipes rec
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,4,5,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[3,4,5]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e cobertura de morango', 1, 4, 18, 18
from public.recipes rec
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=4);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='finalizacao' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[6,7]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa de leite Ninho', 1, 1, 19, 19
from public.recipes rec
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella' and rec.source_page_start=19
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella' and rec.source_page_start=19
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella' and rec.source_page_start=19
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Preparação da forma', 1, 2, 19, 19
from public.recipes rec
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella' and rec.source_page_start=19
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella' and rec.source_page_start=19
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e resfriamento', 1, 3, 19, 19
from public.recipes rec
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella' and rec.source_page_start=19
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella' and rec.source_page_start=19
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[5]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura de Nutella', 1, 4, 19, 19
from public.recipes rec
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella' and rec.source_page_start=19
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=4);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella' and rec.source_page_start=19
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella' and rec.source_page_start=19
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura' and rs.position = any(array[6]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa Romeu e Julieta', 1, 1, 20, 20
from public.recipes rec
where rec.slug='pudim-romeu-e-julieta' and rec.source_page_start=20
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-romeu-e-julieta' and rec.source_page_start=20
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5,6,7]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-romeu-e-julieta' and rec.source_page_start=20
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Preparação da forma', 1, 2, 20, 20
from public.recipes rec
where rec.slug='pudim-romeu-e-julieta' and rec.source_page_start=20
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-romeu-e-julieta' and rec.source_page_start=20
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e resfriamento', 1, 3, 20, 20
from public.recipes rec
where rec.slug='pudim-romeu-e-julieta' and rec.source_page_start=20
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-romeu-e-julieta' and rec.source_page_start=20
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura de goiabada', 1, 4, 20, 20
from public.recipes rec
where rec.slug='pudim-romeu-e-julieta' and rec.source_page_start=20
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=4);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-romeu-e-julieta' and rec.source_page_start=20
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-romeu-e-julieta' and rec.source_page_start=20
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura' and rs.position = any(array[5]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa de Ovomaltine', 1, 1, 21, 21
from public.recipes rec
where rec.slug='pudim-de-ovomaltine' and rec.source_page_start=21
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ovomaltine' and rec.source_page_start=21
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5,6,7]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ovomaltine' and rec.source_page_start=21
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'calda', 'Calda de chocolate e montagem', 1, 2, 21, 21
from public.recipes rec
where rec.slug='pudim-de-ovomaltine' and rec.source_page_start=21
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ovomaltine' and rec.source_page_start=21
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='calda' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ovomaltine' and rec.source_page_start=21
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='calda' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e finalização', 1, 3, 21, 21
from public.recipes rec
where rec.slug='pudim-de-ovomaltine' and rec.source_page_start=21
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ovomaltine' and rec.source_page_start=21
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[5,6]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa de leite Ninho', 1, 1, 22, 22
from public.recipes rec
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella-sem-forno' and rec.source_page_start=22
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella-sem-forno' and rec.source_page_start=22
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5,6,7]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella-sem-forno' and rec.source_page_start=22
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2,3,4,5]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura de Nutella', 1, 2, 22, 22
from public.recipes rec
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella-sem-forno' and rec.source_page_start=22
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella-sem-forno' and rec.source_page_start=22
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella-sem-forno' and rec.source_page_start=22
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura' and rs.position = any(array[6]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa de coco diet', 1, 1, 23, 23
from public.recipes rec
where rec.slug='pudim-de-coco-diet' and rec.source_page_start=23
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-coco-diet' and rec.source_page_start=23
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5,6,7,8]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-coco-diet' and rec.source_page_start=23
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Calda de coco diet e finalização', 1, 2, 23, 23
from public.recipes rec
where rec.slug='pudim-de-coco-diet' and rec.source_page_start=23
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-coco-diet' and rec.source_page_start=23
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-coco-diet' and rec.source_page_start=23
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa do pudim diet', 1, 1, 24, 24
from public.recipes rec
where rec.slug='pudim-diet' and rec.source_page_start=24
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-diet' and rec.source_page_start=24
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-diet' and rec.source_page_start=24
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'calda', 'Calda diet e montagem', 1, 2, 24, 24
from public.recipes rec
where rec.slug='pudim-diet' and rec.source_page_start=24
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-diet' and rec.source_page_start=24
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='calda' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-diet' and rec.source_page_start=24
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='calda' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e finalização', 1, 3, 24, 24
from public.recipes rec
where rec.slug='pudim-diet' and rec.source_page_start=24
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-diet' and rec.source_page_start=24
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[5,6]);

commit;

-- >>>>>>>>>> migrations/20261114043000_structure_paves_components.sql
-- Estrutura os 11 pavês antigos conforme camadas e preparos descritos no receituário original em espanhol.
-- O Pavê Floresta Negra já estruturado fica intocado.
begin;

insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Cremes branco e de chocolate', 1, 1, 3, 3
from public.recipes rec
where rec.slug='pave-de-chocolate' and rec.source_page_start=3
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate' and rec.source_page_start=3
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[1,2,3,4,5,6,10]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate' and rec.source_page_start=3
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[1,2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem e camadas', 1, 2, 3, 3
from public.recipes rec
where rec.slug='pave-de-chocolate' and rec.source_page_start=3
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate' and rec.source_page_start=3
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem' and ri.position = any(array[7,8,9]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate' and rec.source_page_start=3
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[3,4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme base', 1, 1, 5, 5
from public.recipes rec
where rec.slug='pave-de-chocolate-bis' and rec.source_page_start=5
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate-bis' and rec.source_page_start=5
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[1,2,3,4]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate-bis' and rec.source_page_start=5
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[1]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Camada de BIS', 1, 2, 5, 5
from public.recipes rec
where rec.slug='pave-de-chocolate-bis' and rec.source_page_start=5
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate-bis' and rec.source_page_start=5
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem' and ri.position = any(array[5]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate-bis' and rec.source_page_start=5
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura de merengue', 1, 3, 5, 5
from public.recipes rec
where rec.slug='pave-de-chocolate-bis' and rec.source_page_start=5
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate-bis' and rec.source_page_start=5
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura' and ri.position = any(array[6,7]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate-bis' and rec.source_page_start=5
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura' and rs.position = any(array[3,4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'base', 'Base de biscoito', 1, 1, 6, 6
from public.recipes rec
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='base' and ri.position = any(array[1,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='base' and rs.position = any(array[1]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme de limão', 1, 2, 6, 6
from public.recipes rec
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[2,3,4]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem e decoração', 1, 3, 6, 6
from public.recipes rec
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem' and ri.position = any(array[5]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Resfriamento', 1, 4, 6, 6
from public.recipes rec
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=4);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme', 1, 1, 7, 7
from public.recipes rec
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[1,2,3,4,5]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[1]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura', 1, 2, 7, 7
from public.recipes rec
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura' and ri.position = any(array[7,8,9,10]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura' and rs.position = any(array[2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Pão de ló', 1, 3, 7, 7
from public.recipes rec
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[11,12,13,14]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[3,4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem', 1, 4, 7, 7
from public.recipes rec
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=4);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem' and ri.position = any(array[6,15]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[5,6]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Abacaxi caramelizado', 1, 1, 9, 9
from public.recipes rec
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio' and ri.position = any(array[1,2]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio' and rs.position = any(array[1]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme', 1, 2, 9, 9
from public.recipes rec
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[3,4,7]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura de claras', 1, 3, 9, 9
from public.recipes rec
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura' and ri.position = any(array[5,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura' and rs.position = any(array[3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem e finalização', 1, 4, 9, 9
from public.recipes rec
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=4);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem' and ri.position = any(array[8]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[4,5]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme de maracujá', 1, 1, 10, 10
from public.recipes rec
where rec.slug='pave-de-maracuja-e-chocolate' and rec.source_page_start=10
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-maracuja-e-chocolate' and rec.source_page_start=10
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[1,2,3,7]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-maracuja-e-chocolate' and rec.source_page_start=10
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[1,2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura de chocolate', 1, 2, 10, 10
from public.recipes rec
where rec.slug='pave-de-maracuja-e-chocolate' and rec.source_page_start=10
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-maracuja-e-chocolate' and rec.source_page_start=10
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura' and ri.position = any(array[5,6,9]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-maracuja-e-chocolate' and rec.source_page_start=10
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura' and rs.position = any(array[3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem', 1, 3, 10, 10
from public.recipes rec
where rec.slug='pave-de-maracuja-e-chocolate' and rec.source_page_start=10
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-maracuja-e-chocolate' and rec.source_page_start=10
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem' and ri.position = any(array[4,8]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-maracuja-e-chocolate' and rec.source_page_start=10
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[4,5]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'base', 'Camada de uvas', 1, 1, 11, 11
from public.recipes rec
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='base' and ri.position = any(array[1,2]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='base' and rs.position = any(array[1]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme de baunilha', 1, 2, 11, 11
from public.recipes rec
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[3,4,5,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Trufa de chocolate', 1, 3, 11, 11
from public.recipes rec
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura' and ri.position = any(array[7,8]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura' and rs.position = any(array[3,4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Chantilly e decoração', 1, 4, 11, 11
from public.recipes rec
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=4);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='finalizacao' and ri.position = any(array[9,10,11]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[5,6]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme de doce de leite', 1, 1, 13, 13
from public.recipes rec
where rec.slug='pave-de-amendoim' and rec.source_page_start=13
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-amendoim' and rec.source_page_start=13
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[2,3]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-amendoim' and rec.source_page_start=13
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[1]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem com biscoitos e amendoim', 1, 2, 13, 13
from public.recipes rec
where rec.slug='pave-de-amendoim' and rec.source_page_start=13
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-amendoim' and rec.source_page_start=13
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem' and ri.position = any(array[1,4]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-amendoim' and rec.source_page_start=13
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Resfriamento', 1, 3, 13, 13
from public.recipes rec
where rec.slug='pave-de-amendoim' and rec.source_page_start=13
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-amendoim' and rec.source_page_start=13
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme de ameixa', 1, 1, 14, 14
from public.recipes rec
where rec.slug='pave-de-ameixa' and rec.source_page_start=14
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-ameixa' and rec.source_page_start=14
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[1,2,3,4,5,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-ameixa' and rec.source_page_start=14
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[1]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem com biscoitos', 1, 2, 14, 14
from public.recipes rec
where rec.slug='pave-de-ameixa' and rec.source_page_start=14
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-ameixa' and rec.source_page_start=14
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem' and ri.position = any(array[7,8]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-ameixa' and rec.source_page_start=14
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Resfriamento', 1, 3, 14, 14
from public.recipes rec
where rec.slug='pave-de-ameixa' and rec.source_page_start=14
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-ameixa' and rec.source_page_start=14
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme de café e chocolate', 1, 1, 15, 15
from public.recipes rec
where rec.slug='pave-de-cafe' and rec.source_page_start=15
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-cafe' and rec.source_page_start=15
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[1,2,3,5,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-cafe' and rec.source_page_start=15
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[1]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Claras com creme de leite', 1, 2, 15, 15
from public.recipes rec
where rec.slug='pave-de-cafe' and rec.source_page_start=15
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-cafe' and rec.source_page_start=15
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura' and ri.position = any(array[7]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-cafe' and rec.source_page_start=15
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura' and rs.position = any(array[2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem e finalização', 1, 3, 15, 15
from public.recipes rec
where rec.slug='pave-de-cafe' and rec.source_page_start=15
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-cafe' and rec.source_page_start=15
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem' and ri.position = any(array[4]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-cafe' and rec.source_page_start=15
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[3,4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme de chocolate branco', 1, 1, 16, 16
from public.recipes rec
where rec.slug='pave-de-chocolate-branco' and rec.source_page_start=16
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate-branco' and rec.source_page_start=16
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[1,2,3,4,5]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate-branco' and rec.source_page_start=16
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[1,2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem e decoração', 1, 2, 16, 16
from public.recipes rec
where rec.slug='pave-de-chocolate-branco' and rec.source_page_start=16
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate-branco' and rec.source_page_start=16
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem' and ri.position = any(array[6,7]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate-branco' and rec.source_page_start=16
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[4,5]);

commit;

-- >>>>>>>>>> migrations/20261114044500_preserve_torta_ameixa_step_order.sql
-- Preserva a sequência original da Torta de Ameixa com Nozes no modo cozinheiro.
-- O fechamento da massa e a ida ao forno acontecem depois do recheio e antes da cobertura.
begin;

update public.recipe_components rc
set position=4, updated_at=now()
from public.recipes r
where rc.recipe_id=r.id
  and r.slug='torta-de-ameixa-com-nozes'
  and rc.role='cobertura'
  and rc.position=3;

insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select r.id,'montagem','Fechamento e forno',1,3,8,8
from public.recipes r
where r.slug='torta-de-ameixa-com-nozes' and r.source_page_start=8
  and not exists (
    select 1 from public.recipe_components rc
    where rc.recipe_id=r.id and rc.position=3
  );

update public.recipe_steps s
set component_id=rc.id, updated_at=now()
from public.recipes r
join public.recipe_components rc on rc.recipe_id=r.id
where r.slug='torta-de-ameixa-com-nozes'
  and s.recipe_id=r.id
  and s.position=6
  and s.component_id is not null
  and rc.role='montagem'
  and rc.position=3;

commit;

-- >>>>>>>>>> migrations/20261114050000_correct_torta_de_chocolate_component_mapping.sql
-- Corrige a associação da Torta de Chocolate conforme os títulos explícitos da página 5.
-- A lista original aparece nesta ordem: recheio (posições 1–3), massa (4–5) e cobertura (6–7).
-- As etapas seguem: massa (1), recheio (2–3) e cobertura (4).
-- Não cria componentes nem ingredientes; falha se a ficha existente divergir da fonte conferida.
begin;

do $migration$
declare
  target_recipe_id uuid;
  recipe_count integer;
  components_count integer;
  ingredients_count integer;
  ingredients_on_source_page integer;
  steps_count integer;
  steps_on_source_page integer;
begin
  select count(*)
    into recipe_count
  from public.recipes
  where slug = 'torta-de-chocolate'
    and kind = 'recipe'
    and source_page_start = 5
    and source_page_end = 5;

  if recipe_count > 1 then
    raise exception 'Mais de uma Torta de Chocolate foi encontrada na página 5; revisão manual necessária.';
  end if;

  if recipe_count = 1 then
    select id
      into target_recipe_id
    from public.recipes
    where slug = 'torta-de-chocolate'
      and kind = 'recipe'
      and source_page_start = 5
      and source_page_end = 5;

    select count(*)
      into components_count
    from public.recipe_components
    where recipe_id = target_recipe_id;

    if components_count <> 3
      or not exists (
        select 1 from public.recipe_components
        where recipe_id = target_recipe_id and role = 'massa' and title = 'Massa' and position = 1
      )
      or not exists (
        select 1 from public.recipe_components
        where recipe_id = target_recipe_id and role = 'recheio' and title = 'Recheio' and position = 2
      )
      or not exists (
        select 1 from public.recipe_components
        where recipe_id = target_recipe_id and role = 'cobertura' and title = 'Cobertura' and position = 3
      )
    then
      raise exception 'A Torta de Chocolate não possui exatamente os três componentes esperados; nenhum vínculo foi alterado.';
    end if;

    select count(*), count(*) filter (where source_page = 5)
      into ingredients_count, ingredients_on_source_page
    from public.recipe_ingredients
    where recipe_id = target_recipe_id;

    if ingredients_count <> 7
      or ingredients_on_source_page <> 7
      or (select count(distinct position) from public.recipe_ingredients where recipe_id = target_recipe_id) <> 7
      or (select min(position) from public.recipe_ingredients where recipe_id = target_recipe_id) <> 1
      or (select max(position) from public.recipe_ingredients where recipe_id = target_recipe_id) <> 7
    then
      raise exception 'A Torta de Chocolate não possui os 7 ingredientes esperados na página 5; nenhum vínculo foi alterado.';
    end if;

    select count(*), count(*) filter (where source_page = 5)
      into steps_count, steps_on_source_page
    from public.recipe_steps
    where recipe_id = target_recipe_id;

    if steps_count <> 4
      or steps_on_source_page <> 4
      or (select count(distinct position) from public.recipe_steps where recipe_id = target_recipe_id) <> 4
      or (select min(position) from public.recipe_steps where recipe_id = target_recipe_id) <> 1
      or (select max(position) from public.recipe_steps where recipe_id = target_recipe_id) <> 4
    then
      raise exception 'A Torta de Chocolate não possui as 4 etapas esperadas na página 5; nenhum vínculo foi alterado.';
    end if;

    update public.recipe_ingredients as ingredient
    set component_id = component.id,
        updated_at = now()
    from public.recipe_components as component
    where ingredient.recipe_id = target_recipe_id
      and ingredient.source_page = 5
      and component.recipe_id = target_recipe_id
      and (
        (component.role = 'recheio' and ingredient.position between 1 and 3)
        or (component.role = 'massa' and ingredient.position between 4 and 5)
        or (component.role = 'cobertura' and ingredient.position between 6 and 7)
      )
      and ingredient.component_id is distinct from component.id;

    update public.recipe_steps as step
    set component_id = component.id,
        updated_at = now()
    from public.recipe_components as component
    where step.recipe_id = target_recipe_id
      and step.source_page = 5
      and component.recipe_id = target_recipe_id
      and (
        (component.role = 'massa' and step.position = 1)
        or (component.role = 'recheio' and step.position between 2 and 3)
        or (component.role = 'cobertura' and step.position = 4)
      )
      and step.component_id is distinct from component.id;

    if exists (
      select 1
      from public.recipe_ingredients as ingredient
      where ingredient.recipe_id = target_recipe_id
        and not exists (
          select 1
          from public.recipe_components as component
          where component.id = ingredient.component_id
            and component.recipe_id = target_recipe_id
            and (
              (component.role = 'recheio' and ingredient.position between 1 and 3)
              or (component.role = 'massa' and ingredient.position between 4 and 5)
              or (component.role = 'cobertura' and ingredient.position between 6 and 7)
            )
        )
    ) then
      raise exception 'Há ingrediente da Torta de Chocolate sem o componente confirmado pela página 5.';
    end if;

    if exists (
      select 1
      from public.recipe_steps as step
      where step.recipe_id = target_recipe_id
        and not exists (
          select 1
          from public.recipe_components as component
          where component.id = step.component_id
            and component.recipe_id = target_recipe_id
            and (
              (component.role = 'massa' and step.position = 1)
              or (component.role = 'recheio' and step.position between 2 and 3)
              or (component.role = 'cobertura' and step.position = 4)
            )
        )
    ) then
      raise exception 'Há etapa da Torta de Chocolate sem o componente confirmado pela página 5.';
    end if;
  end if;
end
$migration$;

commit;

-- >>>>>>>>>> migrations/20261114051000_restore_publication_integrity_checks.sql
-- Reforça as condições de publicação sem alterar receitas já publicadas.
-- A publicação continua direta no painel, mas exige ficha estruturada, revisão sem
-- avisos/bloqueios pendentes, permissão comercial confirmada quando há fonte e
-- componentes vinculados já publicados.
begin;

create or replace function public.guard_recipe_status()
returns trigger
language plpgsql
set search_path = public
as $function$
declare
  v_permission text;
begin
  if tg_op = 'INSERT' or old.status is distinct from new.status then
    if new.status in ('approved', 'published') then
      if new.content_state is distinct from 'structured' then
        raise exception 'CONTENT_REQUIRED';
      end if;

      if exists (
        select 1
        from public.review_flags
        where recipe_id = new.id
          and resolved_at is null
          and severity in ('warning', 'blocker')
      ) then
        raise exception 'FLAGS_PENDING';
      end if;
    end if;

    if new.status = 'approved' then
      new.reviewed_at := now();
      new.reviewed_by := coalesce(auth.uid(), new.reviewed_by);
    end if;

    if new.status = 'published' then
      if new.source_document_id is not null then
        select commercial_permission
          into v_permission
        from public.source_documents
        where id = new.source_document_id;

        if v_permission is distinct from 'confirmed' then
          raise exception 'PERMISSION_REQUIRED';
        end if;
      end if;

      if exists (
        select 1
        from public.recipe_components component
        join public.recipes linked_recipe on linked_recipe.id = component.linked_recipe_id
        where component.recipe_id = new.id
          and component.linked_recipe_id is not null
          and linked_recipe.status <> 'published'
      ) then
        raise exception 'LINKED_COMPONENT_UNPUBLISHED';
      end if;

      new.published_at := coalesce(new.published_at, now());
    end if;
  end if;

  return new;
end;
$function$;

commit;

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
  ('00135c34-aa9a-5715-98cb-6af65cfc83f6', 'panetones-chocotones-natal', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', 'Receitas 02 de Panetones', 'Autoria própria (informada pelo administrador)', null, 'Receitas 02 de panetones.pdf', 'pt-BR', 115, 'received', null, null, 'unknown', 'O administrador informou que o material é de sua própria autoria. A confirmação formal de permissão comercial permanece sujeita à validação no painel administrativo; não marcar como confirmada neste arquivo.', null, 'Conteúdo transcrito pelo administrador nesta conversa, páginas 8 a 115. A transcrição inclui utensílios, dicas, 25 preparações, massas, recheios, coberturas e montagens. Não foi anexado o PDF binário; referências de página usam a numeração apresentada na transcrição e devem ser conferidas no arquivo original quando disponível.', '[]'::jsonb),
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
  ('f5c19bc6-2479-5ec4-9abe-d4aceecc1f8e', 'agua', 'Água', 'despensa', false),
  ('135274a3-0f44-5575-8124-d73d9da305e9', 'farinha-de-trigo', 'Farinha de trigo', 'mercearia', true),
  ('d56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 'fermento-biologico-seco', 'Fermento biológico seco', 'padaria', true),
  ('0a718c08-62f3-5af3-8577-980614b5cf9d', 'agua-morna', 'Água morna', 'despensa', true),
  ('1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 'essencia-de-baunilha', 'Essência de baunilha', 'confeitaria', true),
  ('8566bb0d-ee09-5d4a-a651-70a1621c1264', 'essencia-de-panetone', 'Essência de Panetone', 'confeitaria', true),
  ('ab8fb758-861c-5312-ae98-f38d81f25e6e', 'limao', 'Limão', 'hortifruti', true),
  ('719de073-c900-5def-808b-af472a1c4be8', 'laranja', 'Laranja', 'hortifruti', true),
  ('0382f024-7c3c-579d-a5c1-ced56cbc2e75', 'margarina-sem-sal', 'Margarina sem sal', 'laticinios', true),
  ('9f52288a-886a-53b0-a056-95e9903995b9', 'manteiga-sem-sal', 'Manteiga sem sal', 'laticinios', true),
  ('9cf7d3c9-36d9-5e20-9c00-6151636b0ac1', 'uva-passa', 'Uvas-passas', 'mercearia', true),
  ('523013e5-3b5c-503c-8e3b-0efe15fa5dda', 'frutas-cristalizadas', 'Frutas cristalizadas', 'mercearia', true),
  ('9b1e65ad-f9ce-50fa-aa1c-9d934b76e83c', 'leite-em-po', 'Leite em pó', 'laticinios', true),
  ('b4f34561-8417-5374-b624-7e5bba20ed3f', 'sal', 'Sal', 'despensa', true),
  ('eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 'gema-de-ovo', 'Gema de ovo', 'laticinios', true),
  ('b9c850ce-e18b-58e0-aaa8-9dad5110b902', 'chocolate-em-gotas', 'Chocolate em gotas', 'confeitaria', true),
  ('9ba768f4-c033-5476-9841-d77490a6ae27', 'chocolate-em-barra', 'Chocolate em barra', 'confeitaria', true),
  ('66de60ad-556e-5d31-a00e-33e3d39f9b10', 'canela-em-po', 'Canela em pó', 'mercearia', true),
  ('d6023bf0-76f4-5247-899b-d967195f1018', 'doce-de-leite', 'Doce de leite', 'laticinios', true),
  ('562bc70c-661f-5b07-8a95-eb8378d53841', 'nutella', 'Nutella', 'confeitaria', true),
  ('298f0828-425b-5991-a12f-fdf8bb2fc461', 'cacau-em-po-50', 'Cacau em pó 50%', 'mercearia', true),
  ('40245c07-39b0-5a2c-b610-edc6bb3fb56b', 'chocolate-branco', 'Chocolate branco', 'confeitaria', true),
  ('226cf1a2-0b7c-5117-8b13-4aad315d34a0', 'chocolate-branco-nobre', 'Chocolate branco nobre', 'confeitaria', true),
  ('cf8c47db-5462-5c96-906c-bd05adf51ea3', 'chocolate-nobre-meio-amargo', 'Chocolate nobre meio amargo', 'confeitaria', true),
  ('b4d783c2-7628-5681-8a23-e61a1d392617', 'ovomaltine', 'Ovomaltine em pó', 'mercearia', true),
  ('045392ee-ad51-52cf-9c5b-2f4e819896df', 'nozes', 'Nozes', 'mercearia', true),
  ('71151d78-31dd-5a06-b9b4-e75b87b5a54b', 'chocolate-meio-amargo-fracionado', 'Chocolate meio amargo fracionado ou tipo cobertura', 'confeitaria', true)
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
  ('adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'chocotone-2-amores', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone 2 Amores', 'CHOCOTONE 2 AMORES', 'pt-BR', 'not_needed', 'Chocotone 2 Amores com massa de chocotone e brigadeiro de chocolate e brigadeiro branco.', null, null, 5, 'Chocotone', 'Chocotones', '500g cada; receita do recheio para 1 unidade de 500g', '5 Chocotones de 500g; recheio para 1 unidade de 500g', null, null, null, 30, null, null, false, null, 73, 76, '{}'::integer[], false, 'structured', 'review', 35, false),
  ('4d2a3954-117b-5bba-bc3f-d10f8fae417d', 'chocotone-alpino', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone Alpino', 'CHOCOTONE ALPINO', 'pt-BR', 'not_needed', 'Chocotone Alpino com massa de chocotone e recheio alpino.', null, null, 5, 'Chocotone', 'Chocotones', '500g cada; receita do recheio para 1 unidade de 500g', '5 Chocotones de 500g; recheio para 1 unidade de 500g', null, null, null, 30, null, null, false, null, 97, 100, '{}'::integer[], false, 'structured', 'review', 41, false),
  ('ceb882d2-0dba-55b5-88d1-89c8e9991514', 'chocotone-de-brigadeiro-gourmet', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone de Brigadeiro Gourmet', 'CHOCOTONE DE BRIGADEIRO GOURMET', 'pt-BR', 'not_needed', 'Chocotone de Brigadeiro Gourmet com massa de chocotone e recheio de brigadeiro gourmet.', null, null, 5, 'Chocotone', 'Chocotones', '500g cada; receita do recheio para 1 unidade de 500g', '5 Chocotones de 500g; recheio para 1 unidade de 500g', null, null, null, 30, null, null, false, null, 57, 60, '{}'::integer[], false, 'structured', 'review', 31, false),
  ('1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', 'chocotone-de-brigadeiro', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone de Brigadeiro', 'CHOCOTONE DE BRIGADEIRO', 'pt-BR', 'not_needed', 'Chocotone de Brigadeiro com massa de chocotone e recheio de brigadeiro.', null, null, 5, 'Chocotone', 'Chocotones', '500g cada; receita do recheio para 1 unidade de 500g', '5 Chocotones de 500g; recheio para 1 unidade de 500g', null, null, null, 30, null, null, false, null, 37, 40, '{}'::integer[], false, 'structured', 'review', 26, false),
  ('f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'chocotone-de-churros', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone de Churros', 'CHOCOTONE DE CHURROS', 'pt-BR', 'not_needed', 'Chocotone com canela, gotas de chocolate e recheio de churros.', null, null, 5, 'Chocotone', 'Chocotones', '500g cada; recheio rende 1 Chocotone', '5 Chocotones de 500g; recheio para 1 Chocotone de 500g', null, null, null, 30, null, null, false, null, 25, 27, '{}'::integer[], false, 'structured', 'review', 3, false),
  ('8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', 'chocotone-de-coco', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone de Coco', 'CHOCOTONE DE COCO', 'pt-BR', 'not_needed', 'Chocotone de Coco com massa de chocotone e recheio de coco.', null, null, 5, 'Chocotone', 'Chocotones', '500g cada; receita do recheio para 1 unidade de 500g', '5 Chocotones de 500g; recheio para 1 unidade de 500g', null, null, null, 30, null, null, false, null, 65, 68, '{}'::integer[], false, 'structured', 'review', 33, false),
  ('f9435243-097a-5129-8c21-10874bac99c9', 'chocotone-de-ninho', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone de Ninho', 'CHOCOTONE DE NINHO', 'pt-BR', 'not_needed', 'Chocotone tradicional com gotas de chocolate, recheio e cobertura de leite em pó.', null, null, 5, 'Chocotone', 'Chocotones', '500g cada; recheio para 1 Chocotone', '5 Chocotones de 500g; recheio para 1 Chocotone de 500g', null, null, null, 30, null, null, false, null, 29, 33, '{}'::integer[], false, 'structured', 'review', 4, false),
  ('3e9a4b0a-d7f0-5047-ac81-784a3e737d71', 'chocotone-de-nutella', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone de Nutella', 'CHOCOTONE DE NUTELLA', 'pt-BR', 'not_needed', 'Chocotone de Nutella com massa de chocotone e recheio de nutella.', null, null, 5, 'Chocotone', 'Chocotones', '500g cada; receita do recheio para 1 unidade de 500g', '5 Chocotones de 500g; recheio para 1 unidade de 500g', null, null, null, 30, null, null, false, null, 61, 64, '{}'::integer[], false, 'structured', 'review', 32, false),
  ('402d03c4-696f-5a06-bc57-60887ac4e688', 'chocotone-de-oreo', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone de Oreo', 'CHOCOTONE DE OREO', 'pt-BR', 'not_needed', 'Chocotone de Oreo com massa de chocotone e recheio de oreo.', null, null, 5, 'Chocotone', 'Chocotones', '500g cada; receita do recheio para 1 unidade de 500g', '5 Chocotones de 500g; recheio para 1 unidade de 500g', null, null, null, 30, null, null, false, null, 69, 72, '{}'::integer[], false, 'structured', 'review', 34, false),
  ('3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'chocotone-dressed', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone Dressed', 'CHOCOTONE DRESSED', 'pt-BR', 'not_needed', 'Chocotone Dressed com massa de chocotone e montagem com placa de textura.', null, null, 5, 'Chocotone', 'Chocotones', '500g cada; receita do recheio para 1 unidade de 500g', '5 Chocotones de 500g; recheio para 1 unidade de 500g', null, null, null, 30, null, null, false, null, 93, 96, '{}'::integer[], false, 'structured', 'review', 40, false),
  ('bc22d3a4-d37b-5496-8975-1a7ee0adc383', 'chocotone-ferrero-rocher', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone Ferrero Rocher', 'CHOCOTONE FERRERO ROCHER', 'pt-BR', 'not_needed', 'Chocotone Ferrero Rocher com massa de chocotone e recheio de ferrero rocher.', null, null, 5, 'Chocotone', 'Chocotones', '500g cada; receita do recheio para 1 unidade de 500g', '5 Chocotones de 500g; recheio para 1 unidade de 500g', null, null, null, 30, null, null, false, null, 34, 37, '{}'::integer[], false, 'structured', 'review', 25, false),
  ('9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'chocotone-infantil', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone Infantil', 'CHOCOTONE INFANTIL', 'pt-BR', 'not_needed', 'Chocotone Infantil com massa de chocotone e recheio de brigadeiro.', null, null, 5, 'Chocotone', 'Chocotones', '500g cada; receita do recheio para 1 unidade de 500g', '5 Chocotones de 500g; recheio para 1 unidade de 500g', null, null, null, 30, null, null, false, null, 109, 112, '{}'::integer[], false, 'structured', 'review', 44, false),
  ('dc77b330-46fd-5257-afaa-235c8c5915f4', 'chocotone-kinder-bueno', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone Kinder Bueno', 'CHOCOTONE KINDER BUENO', 'pt-BR', 'not_needed', 'Chocotone Kinder Bueno com massa de chocotone e recheio kinder bueno.', null, null, 5, 'Chocotone', 'Chocotones', '500g cada; receita do recheio para 1 unidade de 500g', '5 Chocotones de 500g; recheio para 1 unidade de 500g', null, null, null, 30, null, null, false, null, 101, 104, '{}'::integer[], false, 'structured', 'review', 42, false),
  ('155006a3-77a9-5248-bca7-a7624fc3795d', 'chocotone-laka', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone Laka', 'CHOCOTONE LAKA', 'pt-BR', 'not_needed', 'Chocotone Laka com massa de chocotone e recheio de laka.', null, null, 5, 'Chocotone', 'Chocotones', '500g cada; receita do recheio para 1 unidade de 500g', '5 Chocotones de 500g; recheio para 1 unidade de 500g', null, null, null, 30, null, null, false, null, 85, 88, '{}'::integer[], false, 'structured', 'review', 38, false),
  ('ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'chocotone-ovomaltine', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone Ovomaltine', 'CHOCOTONE OVOMALTINE', 'pt-BR', 'not_needed', 'Chocotone Ovomaltine com massa de chocotone e recheio de ovomaltine.', null, null, 5, 'Chocotone', 'Chocotones', '500g cada; receita do recheio para 1 unidade de 500g', '5 Chocotones de 500g; recheio para 1 unidade de 500g', null, null, null, 30, null, null, false, null, 53, 56, '{}'::integer[], false, 'structured', 'review', 30, false),
  ('bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'chocotone-tradicional', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone Tradicional', 'CHOCOTONE TRADICIONAL', 'pt-BR', 'not_needed', 'Chocotone tradicional com gotas de chocolate ou chocolate em barra picado.', null, null, 5, 'Chocotone', 'Chocotones', '500g cada', '5 Chocotones de 500g', null, null, null, 30, null, null, false, null, 22, 24, '{}'::integer[], false, 'structured', 'review', 2, false),
  ('d2af5983-6d59-57ab-b58b-0aabfa5e6c82', 'chocotone-trufado', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Chocotone Trufado', 'CHOCOTONE TRUFADO', 'pt-BR', 'not_needed', 'Chocotone Trufado com massa de chocotone e trufa tradicional.', null, null, 5, 'Chocotone', 'Chocotones', '500g cada; receita do recheio para 1 unidade de 500g', '5 Chocotones de 500g; recheio para 1 unidade de 500g', null, null, null, 30, null, null, false, null, 49, 52, '{}'::integer[], false, 'structured', 'review', 29, false),
  ('47d81496-9268-5d71-9e83-4475e751a3af', 'panetone-chocotone-no-pote', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Panetone/Chocotone no Pote', 'PANETONE/CHOCOTONE NO POTE', 'pt-BR', 'not_needed', 'Sobremesa no pote com miolo de Panetone ou Chocotone, calda e recheio à escolha.', null, null, 3, 'Potes', 'Potes', 'potes de 250ml; rendimento médio informado para cada receita de recheio', 'Em média, cada receita de recheio rende 3 Panetones no pote', null, null, null, null, null, null, false, null, 113, 115, '{}'::integer[], false, 'structured', 'review', 45, false),
  ('7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', 'panetone-com-cobertura-natalina', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Panetone com Cobertura Natalina', 'PANETONE COM COBERTURA NATALINA', 'pt-BR', 'not_needed', 'Panetone com Cobertura Natalina com massa de panetone e cobertura natalina.', null, null, 5, 'Panetone', 'Panetones', '500g cada; receita do recheio para 1 unidade de 500g', '5 Panetones de 500g; recheio para 1 unidade de 500g', null, null, null, 30, null, null, false, null, 89, 92, '{}'::integer[], false, 'structured', 'review', 39, false),
  ('1c9854b0-80e8-539a-af7a-579821d382c9', 'panetone-de-doce-de-leite-com-ameixas', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Panetone de Doce de Leite com Ameixas', 'PANETONE DE DOCE DE LEITE COM AMEIXAS', 'pt-BR', 'not_needed', 'Panetone de Doce de Leite com Ameixas com massa de panetone e recheio de doce de leite com ameixa.', null, null, 5, 'Panetone', 'Panetones', '500g cada; receita do recheio para 1 unidade de 500g', '5 Panetones de 500g; recheio para 1 unidade de 500g', null, null, null, 30, null, null, false, null, 81, 84, '{}'::integer[], false, 'structured', 'review', 37, false),
  ('c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'panetone-de-morango', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Panetone de Morango', 'PANETONE DE MORANGO', 'pt-BR', 'not_needed', 'Panetone de Morango com massa de panetone e recheio de morango.', null, null, 5, 'Panetone', 'Panetones', '500g cada; receita do recheio para 1 unidade de 500g', '5 Panetones de 500g; recheio para 1 unidade de 500g', null, null, null, 30, null, null, false, null, 41, 44, '{}'::integer[], false, 'structured', 'review', 27, false),
  ('6a8c669b-816b-5cf2-9774-2d16d24209bb', 'panetone-de-nozes', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Panetone de Nozes', 'PANETONE DE NOZES', 'pt-BR', 'not_needed', 'Panetone de Nozes com massa de panetone e recheio de brigadeiro branco com nozes.', null, null, 5, 'Panetone', 'Panetones', '500g cada; receita do recheio para 1 unidade de 500g', '5 Panetones de 500g; recheio para 1 unidade de 500g', null, null, null, 30, null, null, false, null, 77, 80, '{}'::integer[], false, 'structured', 'review', 36, false),
  ('d4a503e9-6658-5cc1-9ff8-f27a4f989268', 'panetone-red-velvet-com-recheio-de-limao', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Panetone Red Velvet com Recheio de Limão', 'PANETONE RED VELVET COM RECHEIO DE LIMÃO', 'pt-BR', 'not_needed', 'Panetone Red Velvet com Recheio de Limão com massa de panetone e recheio de limão.', null, null, 5, 'Panetone', 'Panetones', '500g cada; receita do recheio para 1 unidade de 500g', '5 Panetones de 500g; recheio para 1 unidade de 500g', null, null, null, 30, null, null, false, null, 105, 108, '{}'::integer[], false, 'structured', 'review', 43, false),
  ('d2ff7c98-1883-52ee-8f1d-b725b581dca4', 'panetone-tradicional', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Panetone Tradicional', 'PANETONE TRADICIONAL', 'pt-BR', 'not_needed', 'Panetone tradicional com uvas-passas e frutas cristalizadas.', null, null, 5, 'Panetone', 'Panetones', '500g cada', '5 Panetones de 500g', null, null, null, 30, null, null, false, null, 18, 20, '{}'::integer[], false, 'structured', 'review', 1, false),
  ('f162e20a-72c7-544c-b8dc-77abfd74956a', 'panetone-trufado-de-maracuja', 'baadf930-32cf-54ee-9242-59f7f1bc55d8', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'recipe', null, null, 'Panetone Trufado de Maracujá', 'PANETONE TRUFADO DE MARACUJÁ', 'pt-BR', 'not_needed', 'Panetone Trufado de Maracujá com massa de panetone e recheio de maracujá.', null, null, 5, 'Panetone', 'Panetones', '500g cada; receita do recheio para 1 unidade de 500g', '5 Panetones de 500g; recheio para 1 unidade de 500g', null, null, null, 30, null, null, false, null, 45, 48, '{}'::integer[], false, 'structured', 'review', 28, false),
  ('480e2ce8-4ca0-5937-901c-dfd4635b091a', 'pave-floresta-negra-com-creme-danete', '429a72fd-5f48-5b8b-bb59-02f2d613a2ef', '78bdc3dc-b4a3-5f2d-ab98-face3f488038', 'recipe', null, null, 'Pavê Floresta Negra com Creme Danete', 'PAVÊ FLORESTA NEGRA', 'pt-BR', 'not_needed', 'Sobremesa leve e saborosa para o cardápio de Natal. Na montagem vão bolacha champanhe, creme de leite fresco, cerejas em calda e o creme danete, com finalização de granulé, brigadeiros e cerejas frescas.', '/images/rec-pave-floresta-negra.jpg', null, 1, 'travessa', 'travessas', '27 × 17 cm', '1 travessa de 27 × 17 cm', null, null, null, null, 360, null, true, null, 4, 8, '{3,9,10}'::integer[], true, 'structured', 'review', 12, true)
on conflict (slug) do update set
  collection_id = excluded.collection_id, source_document_id = excluded.source_document_id, kind = excluded.kind, component_role = excluded.component_role, flavor = excluded.flavor, title = excluded.title, original_title = excluded.original_title, original_language = excluded.original_language, translation_status = excluded.translation_status, description = excluded.description, cover_image = excluded.cover_image, difficulty = excluded.difficulty, yield_quantity = excluded.yield_quantity, yield_unit = excluded.yield_unit, yield_unit_plural = excluded.yield_unit_plural, yield_detail = excluded.yield_detail, yield_text = excluded.yield_text, servings = excluded.servings, prep_minutes = excluded.prep_minutes, cook_minutes = excluded.cook_minutes, bake_minutes = excluded.bake_minutes, chill_minutes = excluded.chill_minutes, rest_minutes = excluded.rest_minutes, chill_is_minimum = excluded.chill_is_minimum, measure_note = excluded.measure_note, source_page_start = excluded.source_page_start, source_page_end = excluded.source_page_end, source_pages_extra = excluded.source_pages_extra, page_ref_verified = excluded.page_ref_verified, content_state = excluded.content_state, status = excluded.status, position = excluded.position, is_featured = excluded.is_featured
  where public.recipes.content_state = 'catalogued';


-- Ficha: Chocotone 2 Amores
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = 'adcc7a3e-6f20-55bf-b325-b80c9433bd04')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = 'adcc7a3e-6f20-55bf-b325-b80c9433bd04')
     and not exists (select 1 from public.recipe_steps where recipe_id = 'adcc7a3e-6f20-55bf-b325-b80c9433bd04') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('b2de30ba-3415-54da-8dc8-44f4dd90a5a6', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', null, 'esponja', 'Esponja', null, null, 1, 1, 73, 74),
      ('e01c1ecb-3872-584a-a924-a7e1b3a023b5', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', null, 'massa', 'Massa do Chocotone', null, null, 1, 2, 73, 74),
      ('3b0a84f7-8dba-5c6d-8689-50d9baa39d2a', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', null, 'recheio', 'Brigadeiro de Chocolate e Brigadeiro Branco', null, null, 1, 3, 75, 76),
      ('00a5701d-4368-5761-84ae-fb7bc1634cf6', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', null, 'montagem', 'Montagem — Chocotone 2 Amores', null, null, 1, 4, 75, 76)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('62bfffbc-b728-5d69-9364-784fcef51f62', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'b2de30ba-3415-54da-8dc8-44f4dd90a5a6', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 73, false),
      ('a40e7d45-898a-5566-97bd-ef63a9fe6b01', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'b2de30ba-3415-54da-8dc8-44f4dd90a5a6', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 73, false),
      ('38a8f33e-9fd2-5ca9-8a77-9a65cb6148f1', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'b2de30ba-3415-54da-8dc8-44f4dd90a5a6', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 73, false),
      ('5277f7ea-98ca-5917-91d8-c366856b07ae', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'e01c1ecb-3872-584a-a924-a7e1b3a023b5', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 73, false),
      ('5ea5e620-e22e-5de6-a075-51defc2aa0ba', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'e01c1ecb-3872-584a-a924-a7e1b3a023b5', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 73, false),
      ('1d4b4a1d-8b4f-5e6b-8263-174bfc04edcf', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'e01c1ecb-3872-584a-a924-a7e1b3a023b5', null, 3, 5, null, 'colheres (sopa)', null, 'Leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 73, false),
      ('16f33fe5-64da-51b7-b81a-39d9f434f8c3', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'e01c1ecb-3872-584a-a924-a7e1b3a023b5', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 73, false),
      ('d2d38e49-bd9a-532e-b3a4-d75b3eea7ccc', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'e01c1ecb-3872-584a-a924-a7e1b3a023b5', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 73, false),
      ('eecc75df-a3cf-5660-9c0e-a84ea4ce33ea', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'e01c1ecb-3872-584a-a924-a7e1b3a023b5', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 73, false),
      ('ad6e1b5f-84c8-5474-a989-a59bb3f946e2', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'e01c1ecb-3872-584a-a924-a7e1b3a023b5', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 73, false),
      ('59fdb504-0989-5c48-b8dc-2c65f359c243', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'e01c1ecb-3872-584a-a924-a7e1b3a023b5', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 73, false),
      ('9ed03467-261b-59f6-95f4-3108c1a78966', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'e01c1ecb-3872-584a-a924-a7e1b3a023b5', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 73, false),
      ('b9fd8aec-3e5b-549a-9d1a-442682e54baf', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'e01c1ecb-3872-584a-a924-a7e1b3a023b5', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 73, false),
      ('c7c8bddf-d337-5192-a046-64040faaf20d', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'e01c1ecb-3872-584a-a924-a7e1b3a023b5', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 73, false),
      ('6a582420-9ca2-5788-bb51-c7bcd9f0664a', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'e01c1ecb-3872-584a-a924-a7e1b3a023b5', 'b9c850ce-e18b-58e0-aaa8-9dad5110b902', 12, 350, null, 'g', null, 'chocolate em gotas ou chocolate em barra picado', null, null, 'linear', false, '350g de chocolate em gotas ou chocolate em barra picado', 73, false),
      ('afd63da9-2c05-531f-876a-1b78acdb78f3', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', '3b0a84f7-8dba-5c6d-8689-50d9baa39d2a', '6b34b876-9b3f-5612-96da-1abcf6f11bbc', 1, 1, null, 'unidade', null, 'leite condensado', null, null, 'linear', false, '1 leite condensado', 75, false),
      ('32c86765-b682-5ef5-bc47-08d7728fe8a7', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', '3b0a84f7-8dba-5c6d-8689-50d9baa39d2a', '8758d73e-4fcf-508e-940d-635708436a41', 2, 1, null, 'unidade', null, 'creme de leite', null, null, 'linear', false, '1 creme de leite', 75, false),
      ('f73684bd-b659-51cf-aa81-d2e94749b52d', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', '3b0a84f7-8dba-5c6d-8689-50d9baa39d2a', null, 3, 50, null, 'g', null, 'cacau 50%', null, null, 'linear', false, '50g de cacau 50%', 75, false),
      ('db3f9809-0407-590d-88a7-938f1558e4ef', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', '3b0a84f7-8dba-5c6d-8689-50d9baa39d2a', '6b34b876-9b3f-5612-96da-1abcf6f11bbc', 4, 1, null, 'unidade', null, 'leite condensado', null, null, 'linear', false, '1 leite condensado (brigadeiro branco)', 75, false),
      ('472b50f8-8137-5291-870b-eaba1c358117', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', '3b0a84f7-8dba-5c6d-8689-50d9baa39d2a', '8758d73e-4fcf-508e-940d-635708436a41', 5, 1, null, 'unidade', null, 'creme de leite', null, null, 'linear', false, '1 creme de leite (brigadeiro branco)', 75, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('bf559df3-5d4d-5a5c-b6ed-84d1e37505f6', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'b2de30ba-3415-54da-8dc8-44f4dd90a5a6', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 74, false),
      ('58aefe9c-8c62-579b-81a9-82dbc878e907', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'b2de30ba-3415-54da-8dc8-44f4dd90a5a6', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 74, false),
      ('b3859aef-ce86-5953-b4f7-470b71bb6051', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'e01c1ecb-3872-584a-a924-a7e1b3a023b5', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 74, false),
      ('7d060c3d-ebf1-5daa-ac0b-7d3b7b55909b', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'e01c1ecb-3872-584a-a924-a7e1b3a023b5', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 74, false),
      ('3db89566-6385-507b-b1d8-472c27dcc86d', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'e01c1ecb-3872-584a-a924-a7e1b3a023b5', 3, 'Acrescente a margarina e sove até atingir o ponto de véu, esticando uma pequena porção até ficar transparente sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 74, false),
      ('5e0e318b-42c5-5a9d-90dc-91af2069968e', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'e01c1ecb-3872-584a-a924-a7e1b3a023b5', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente. A massa é macia e pegajosa, e suas mãos precisam do óleo para mexer.', null, 74, false),
      ('0931bd3c-4dba-5e16-b31f-7dae25c1f744', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'e01c1ecb-3872-584a-a924-a7e1b3a023b5', 5, 'Abra a massa em superfície untada com óleo e espalhe as gotas de chocolate; enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as gotas de chocolate. Enrole bem e modele formando uma bola', null, 74, false),
      ('440b483c-b3b6-5f68-8ff1-97fe0c4932e4', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'e01c1ecb-3872-584a-a924-a7e1b3a023b5', 6, 'Coloque em uma tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 75, false),
      ('81e5d390-a8b7-5fa8-9088-6109b95e1b72', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'e01c1ecb-3872-584a-a924-a7e1b3a023b5', 7, 'Volte para a superfície untada, divida em duas partes do mesmo tamanho e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 75, false),
      ('f60305d6-0a0e-5c7a-ad8a-54b52a2de998', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'e01c1ecb-3872-584a-a924-a7e1b3a023b5', 8, 'Aguarde a massa crescer até a borda e asse em forno preaquecido a 180 graus por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 75, false),
      ('373dfa4c-aded-5fb7-9748-78bcf1cc45b4', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'e01c1ecb-3872-584a-a924-a7e1b3a023b5', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 75, false),
      ('9568ce56-a155-5a6e-8a23-4cd795ead60a', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', '3b0a84f7-8dba-5c6d-8689-50d9baa39d2a', 1, 'Brigadeiro de chocolate: misture o leite condensado, o creme de leite e o cacau em panela de fundo grosso; leve ao fogo, mexendo em movimentos circulares até engrossar e aparecer o fundo da panela.', 'Brigadeiro de chocolate: misture o leite condensado, o creme de leite e o cacau em panela de fundo grosso; leve ao fogo, mexendo em movimentos circulares até engrossar e aparecer o fundo da panela.', null, 75, false),
      ('b364796b-6e81-5b32-ae59-0007804283a5', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', '3b0a84f7-8dba-5c6d-8689-50d9baa39d2a', 2, 'Brigadeiro branco: misture o leite condensado e o creme de leite em panela de fundo grosso; leve ao fogo, mexendo em movimentos circulares até engrossar e aparecer o fundo da panela.', 'Brigadeiro branco: misture o leite condensado e o creme de leite em panela de fundo grosso; leve ao fogo, mexendo em movimentos circulares até engrossar e aparecer o fundo da panela.', null, 76, false),
      ('4bc9b82b-03db-564a-8b42-76764d62604b', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', '00a5701d-4368-5761-84ae-fb7bc1634cf6', 1, 'Corte o topo do Chocotone e reserve.', 'Comece cortando o topo do Chocotone e reserve.', null, 75, false),
      ('e60cfe13-44a9-5984-8c53-7f8336cc5d6e', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', '00a5701d-4368-5761-84ae-fb7bc1634cf6', 2, 'Abra uma cavidade com faca e colher, deixando um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Chocotone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Chocotone não perder a estrutura e quebrar).', null, 76, false),
      ('2fc53749-b676-5471-89d7-c1b3f02e2341', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', '00a5701d-4368-5761-84ae-fb7bc1634cf6', 3, 'Adicione o recheio com uma colher ou saco de confeitar.', 'Depois adicione o recheio com uma colher ou um saco de confeitar. Adicione os recheios lado a lado ou em camadas. Finalize com os dois recheios no topo.', null, 76, false),
      ('11eb9209-59bb-5a1b-8456-d117d810ceae', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', '00a5701d-4368-5761-84ae-fb7bc1634cf6', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa, quando indicado na receita.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 76, false),
      ('1077ee69-bb23-5045-b69d-7765ffcbd924', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', '00a5701d-4368-5761-84ae-fb7bc1634cf6', 5, 'Recoloque a tampa e finalize conforme a decoração indicada na receita.', 'Por último coloque a tampa do seu Panetone/Chocotone e decore da maneira de sua preferência, usando sua criatividade.', null, 76, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('61d66353-043a-5cbf-a9eb-6959051eacd1', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'natal'),
      ('d9cf0ccf-15cb-5d7d-b979-e56fe99b28a1', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'chocotone')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('127ea265-e08e-5d2a-936e-3621754f65ef', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', null, 'recipe', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'yield', 'warning', 'A apostila informa rendimento de 5 unidades de 500g, mas também orienta dividir a massa em duas partes. Confirmar o rendimento na revisão.', 74),
      ('af9792fc-5d2b-5432-aefb-502caa507c14', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', null, 'recipe', 'adcc7a3e-6f20-55bf-b325-b80c9433bd04', 'source_pages', 'warning', 'Paginação baseada na transcrição enviada; conferir no PDF original antes da publicação.', 73)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Chocotone Alpino
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = '4d2a3954-117b-5bba-bc3f-d10f8fae417d')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = '4d2a3954-117b-5bba-bc3f-d10f8fae417d')
     and not exists (select 1 from public.recipe_steps where recipe_id = '4d2a3954-117b-5bba-bc3f-d10f8fae417d') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('0fa96fad-ec9f-533c-8983-7bdca6c3d58d', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', null, 'esponja', 'Esponja', null, null, 1, 1, 97, 98),
      ('91d40fcf-20f4-50c2-8d97-f1a8b66e9110', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', null, 'massa', 'Massa do Chocotone', null, null, 1, 2, 97, 98),
      ('3b6ae6fe-4d1c-572a-97ea-edf1d0a322a7', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', null, 'recheio', 'Recheio Alpino', null, null, 1, 3, 99, 100),
      ('12332d57-a081-54ed-96e9-be912a6181de', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', null, 'montagem', 'Montagem — Chocotone Alpino', null, null, 1, 4, 99, 100)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('d30d1e73-7003-58a3-9a36-57fb5899e408', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '0fa96fad-ec9f-533c-8983-7bdca6c3d58d', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 97, false),
      ('3dc79227-ea1d-5677-a3de-4e9f16e698aa', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '0fa96fad-ec9f-533c-8983-7bdca6c3d58d', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 97, false),
      ('fff4f4c4-6726-533f-95ef-06f85a5c79e1', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '0fa96fad-ec9f-533c-8983-7bdca6c3d58d', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 97, false),
      ('4adf6009-f4af-5c33-b087-31e200702aca', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '91d40fcf-20f4-50c2-8d97-f1a8b66e9110', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 97, false),
      ('1f0489ec-e447-5f1a-80c7-3f8bdfc529fb', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '91d40fcf-20f4-50c2-8d97-f1a8b66e9110', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 97, false),
      ('a210c7d4-0a46-5774-a973-088cc0662cfd', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '91d40fcf-20f4-50c2-8d97-f1a8b66e9110', null, 3, 5, null, 'colheres (sopa)', null, 'Leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 97, false),
      ('a863c12f-5e82-5eea-a5ff-d383e44362dc', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '91d40fcf-20f4-50c2-8d97-f1a8b66e9110', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 97, false),
      ('b7807ea5-b37c-550c-9a34-1c18f36bb40b', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '91d40fcf-20f4-50c2-8d97-f1a8b66e9110', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 97, false),
      ('2a3eb6f8-1fb4-528e-8fa5-e7b0b36bef32', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '91d40fcf-20f4-50c2-8d97-f1a8b66e9110', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 97, false),
      ('b6c88afd-f1b4-5763-ac55-4f294b4fddb6', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '91d40fcf-20f4-50c2-8d97-f1a8b66e9110', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 97, false),
      ('b5c6bbe1-a363-5960-a4ae-044c3707e703', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '91d40fcf-20f4-50c2-8d97-f1a8b66e9110', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 97, false),
      ('c61375b1-65e8-5208-a3b1-994fad40fc5c', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '91d40fcf-20f4-50c2-8d97-f1a8b66e9110', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 97, false),
      ('27029bf1-457b-5c48-8f80-9a261e5a6fb5', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '91d40fcf-20f4-50c2-8d97-f1a8b66e9110', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 97, false),
      ('839e5b77-3053-5137-b352-54f77e549cfe', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '91d40fcf-20f4-50c2-8d97-f1a8b66e9110', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 97, false),
      ('6457375f-a8c4-5127-b7b1-5778199670b2', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '91d40fcf-20f4-50c2-8d97-f1a8b66e9110', 'b9c850ce-e18b-58e0-aaa8-9dad5110b902', 12, 350, null, 'g', null, 'chocolate em gotas ou chocolate em barra picado', null, null, 'linear', false, '350g de chocolate em gotas ou chocolate em barra picado', 97, false),
      ('bd1e06d4-36b1-5424-b0dc-c05050d264de', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '3b6ae6fe-4d1c-572a-97ea-edf1d0a322a7', '8758d73e-4fcf-508e-940d-635708436a41', 1, 1, null, 'unidade', null, 'creme de leite', null, null, 'linear', false, '1 creme de leite', 99, false),
      ('f75b48db-aa04-5435-b684-a404a6ebdb6c', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '3b6ae6fe-4d1c-572a-97ea-edf1d0a322a7', 'd6023bf0-76f4-5247-899b-d967195f1018', 2, 400, null, 'g', null, 'doce de leite', null, null, 'linear', false, '1 doce de leite (400g)', 99, false),
      ('ae3f405e-dd44-5598-99d4-146aad3149fc', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '3b6ae6fe-4d1c-572a-97ea-edf1d0a322a7', 'ba6fe174-cf59-5fcc-b16e-1c364477c3e5', 3, 2, null, 'colheres (sopa)', null, 'chocolate em pó', null, null, 'linear', false, '2 colheres (sopa) chocolate em pó', 99, false),
      ('4006dbe7-a714-57e9-b686-69b42160e8a2', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '3b6ae6fe-4d1c-572a-97ea-edf1d0a322a7', null, 4, 300, null, 'g', null, 'chocolate meio amargo ou Alpino', null, null, 'linear', false, '300g chocolate meio amargo ou alpino', 99, false),
      ('83bd2e46-6fad-53b1-814b-f60571182452', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '3b6ae6fe-4d1c-572a-97ea-edf1d0a322a7', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 5, 1, null, 'colher (chá)', null, 'essência de baunilha', null, null, 'linear', false, '1 colher (chá) essência de baunilha', 99, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('8cad1ce9-5603-5153-b474-b209b65e81e3', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '0fa96fad-ec9f-533c-8983-7bdca6c3d58d', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 98, false),
      ('e349f6a1-451c-5106-91d3-b9f84d59e609', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '0fa96fad-ec9f-533c-8983-7bdca6c3d58d', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 98, false),
      ('699778db-598a-59f1-a247-6249cc52d68d', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '91d40fcf-20f4-50c2-8d97-f1a8b66e9110', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 98, false),
      ('5167333b-c399-53b6-8628-72078327e9fc', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '91d40fcf-20f4-50c2-8d97-f1a8b66e9110', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 98, false),
      ('84d95817-6250-5bfa-8702-a2777cea1c23', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '91d40fcf-20f4-50c2-8d97-f1a8b66e9110', 3, 'Acrescente a margarina e sove até atingir o ponto de véu, esticando uma pequena porção até ficar transparente sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 98, false),
      ('3c6be196-1139-5da7-9822-908316919128', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '91d40fcf-20f4-50c2-8d97-f1a8b66e9110', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente. A massa é macia e pegajosa, e suas mãos precisam do óleo para mexer.', null, 98, false),
      ('a1a406c0-59aa-5331-8289-d8aa4ded158b', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '91d40fcf-20f4-50c2-8d97-f1a8b66e9110', 5, 'Abra a massa em superfície untada com óleo e espalhe as gotas de chocolate; enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as gotas de chocolate. Enrole bem e modele formando uma bola', null, 98, false),
      ('a04cb904-04a9-51f6-a2b5-dfd26cdbfdf7', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '91d40fcf-20f4-50c2-8d97-f1a8b66e9110', 6, 'Coloque em uma tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 99, false),
      ('8e8998c7-86ae-5dd1-838b-9fbd9ba2ab91', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '91d40fcf-20f4-50c2-8d97-f1a8b66e9110', 7, 'Volte para a superfície untada, divida em duas partes do mesmo tamanho e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 99, false),
      ('f88d77d2-eaa2-5083-99bf-0de640d4c4b4', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '91d40fcf-20f4-50c2-8d97-f1a8b66e9110', 8, 'Aguarde a massa crescer até a borda e asse em forno preaquecido a 180 graus por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 99, false),
      ('8bbbb279-8fd4-577c-a2fa-f14bc9c98f25', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '91d40fcf-20f4-50c2-8d97-f1a8b66e9110', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 99, false),
      ('b0a0c0e3-fdd1-5de4-b2d5-e476e70872a6', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '3b6ae6fe-4d1c-572a-97ea-edf1d0a322a7', 1, 'Derreta o chocolate em banho-maria ou no micro-ondas e reserve.', 'Derreta o chocolate em banho-maria ou no micro-ondas e reserve.', null, 99, false),
      ('3ec612d4-4e7f-55ef-9f9b-17ef77cb3929', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '3b6ae6fe-4d1c-572a-97ea-edf1d0a322a7', 2, 'Na batedeira, misture o creme de leite, o chocolate em pó, o doce de leite e a baunilha.', 'Na batedeira, misture o creme de leite, o chocolate em pó, o doce de leite e a baunilha.', null, 100, false),
      ('62faebf1-2a08-5157-937f-c2227cb812ee', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '3b6ae6fe-4d1c-572a-97ea-edf1d0a322a7', 3, 'Adicione o chocolate derretido e bata até ficar homogêneo.', 'Adicione o chocolate derretido e bata até ficar homogêneo.', null, 100, false),
      ('0f565251-92aa-5999-a9bc-4f46fbd23409', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '3b6ae6fe-4d1c-572a-97ea-edf1d0a322a7', 4, 'Espere esfriar para que fique um creme consistente.', 'Espere esfriar para que fique um creme consistente.', null, 100, false),
      ('382afea2-c555-5b8c-bb36-cb422aee4780', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '12332d57-a081-54ed-96e9-be912a6181de', 1, 'Corte o topo do Chocotone e reserve.', 'Comece cortando o topo do Chocotone e reserve.', null, 99, false),
      ('5790063f-b535-53fc-b6ab-171dc51ae724', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '12332d57-a081-54ed-96e9-be912a6181de', 2, 'Abra uma cavidade com faca e colher, deixando um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Chocotone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Chocotone não perder a estrutura e quebrar).', null, 100, false),
      ('1522242f-6d86-5a0d-afbd-d063252f2465', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '12332d57-a081-54ed-96e9-be912a6181de', 3, 'Adicione o recheio com uma colher ou saco de confeitar.', 'Depois adicione o recheio com uma colher ou um saco de confeitar. Finalize com um pouco do recheio e pedaços de chocolate.', null, 100, false),
      ('342af218-e964-558f-9348-cb10f3e38555', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '12332d57-a081-54ed-96e9-be912a6181de', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa, quando indicado na receita.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 100, false),
      ('1594d7cd-f4b8-59de-ba97-0fa9dd9e3cb1', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', '12332d57-a081-54ed-96e9-be912a6181de', 5, 'Recoloque a tampa e finalize conforme a decoração indicada na receita.', 'Por último coloque a tampa do seu Panetone/Chocotone e decore da maneira de sua preferência, usando sua criatividade.', null, 100, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('563aa6e1-a839-568a-8080-a58757892dba', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', 'natal'),
      ('e887272e-2ec3-54e6-823c-2fa3fc6dcacf', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', 'chocotone')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('ce77de53-3dab-5c46-bc82-4273b9d7c142', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', null, 'recipe', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', 'yield', 'warning', 'A apostila informa rendimento de 5 unidades de 500g, mas também orienta dividir a massa em duas partes. Confirmar o rendimento na revisão.', 98),
      ('25b6b2de-41e2-5ee6-aac3-7f7aab97c617', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', null, 'recipe', '4d2a3954-117b-5bba-bc3f-d10f8fae417d', 'source_pages', 'warning', 'Paginação baseada na transcrição enviada; conferir no PDF original antes da publicação.', 97)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Chocotone de Brigadeiro Gourmet
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = 'ceb882d2-0dba-55b5-88d1-89c8e9991514')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = 'ceb882d2-0dba-55b5-88d1-89c8e9991514')
     and not exists (select 1 from public.recipe_steps where recipe_id = 'ceb882d2-0dba-55b5-88d1-89c8e9991514') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('205a81aa-6fcb-50de-9853-40623f88ea06', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', null, 'esponja', 'Esponja', null, null, 1, 1, 57, 58),
      ('3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', null, 'massa', 'Massa do Chocotone', null, null, 1, 2, 57, 58),
      ('06aded77-6774-5767-bcc8-e04d6eb9df80', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', null, 'recheio', 'Recheio de Brigadeiro Gourmet', null, null, 1, 3, 59, 60),
      ('e2bfa9ac-a34a-5a45-9c81-5ef24aa79e34', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', null, 'montagem', 'Montagem — Chocotone de Brigadeiro Gourmet', null, null, 1, 4, 59, 60)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('50b66c2f-31b9-5962-b280-ec57fb549c4b', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '205a81aa-6fcb-50de-9853-40623f88ea06', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 57, false),
      ('210dcabf-cfd7-5b8a-a93e-8a0198df778e', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '205a81aa-6fcb-50de-9853-40623f88ea06', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 57, false),
      ('19e7dba2-3362-50aa-a1d5-eb9dcddf7eee', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '205a81aa-6fcb-50de-9853-40623f88ea06', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 57, false),
      ('49315ddb-6286-5689-9e17-7f6114ca7f41', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 57, false),
      ('a3dbe449-7921-58f0-b309-ba20d614e77b', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 57, false),
      ('88080f25-dcd9-5c43-a0f7-f53b30e1f783', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', null, 3, 5, null, 'colheres (sopa)', null, 'Leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 57, false),
      ('b6fb2b27-38c0-5f2d-9a25-3d22a0f84a8c', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 57, false),
      ('8f5c12df-a31d-5cd5-8cba-6cc74602364b', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 57, false),
      ('a672287a-6adc-5399-8ea1-2e1761d8b5a7', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 57, false),
      ('0af851bd-9d4e-510f-8a6b-60c6daea460f', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 57, false),
      ('2c880452-e43c-5f25-92f0-c0bc9e37d7de', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 57, false),
      ('89f847ae-5fa5-5f51-8de8-86c61dec2664', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 57, false),
      ('b86188ca-8080-5335-8b3c-b34c6e4f3eb5', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 57, false),
      ('f6cc5ec1-0002-509e-8604-f4813a68af61', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 57, false),
      ('985502cd-e5d9-5c84-98e8-d873d831568b', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', 'b9c850ce-e18b-58e0-aaa8-9dad5110b902', 12, 350, null, 'g', null, 'chocolate em gotas ou chocolate em barra picado', null, null, 'linear', false, '350g de chocolate em gotas ou chocolate em barra picado', 57, false),
      ('b79e829e-d9ae-57e6-ace3-53db331e9806', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '06aded77-6774-5767-bcc8-e04d6eb9df80', '6b34b876-9b3f-5612-96da-1abcf6f11bbc', 1, 1, null, 'unidade', null, 'leite condensado', null, null, 'linear', false, '1 leite condensado', 59, false),
      ('0f99e624-71e9-535f-8c2b-019017a4fdca', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '06aded77-6774-5767-bcc8-e04d6eb9df80', null, 2, 1, null, 'colher (café)', null, 'manteiga', null, null, 'linear', false, '1 colher (café) manteiga', 59, false),
      ('23a3d83c-525d-5049-9cc3-10e33e7d52ea', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '06aded77-6774-5767-bcc8-e04d6eb9df80', '8758d73e-4fcf-508e-940d-635708436a41', 3, 1, null, 'unidade', null, 'creme de leite', null, null, 'linear', false, '1 creme de leite', 59, false),
      ('5b88034c-f7ea-56b4-bdce-2af0ed688c59', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '06aded77-6774-5767-bcc8-e04d6eb9df80', null, 4, 50, null, 'g', null, 'cacau 50%', null, null, 'linear', false, '50g de cacau 50%', 59, false),
      ('341de322-8f3d-59f6-a2bc-905668035b84', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '06aded77-6774-5767-bcc8-e04d6eb9df80', 'cf8c47db-5462-5c96-906c-bd05adf51ea3', 5, 50, null, 'g', null, 'chocolate nobre meio amargo', null, null, 'linear', false, '50g de Chocolate nobre meio amargo', 59, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('50cec17e-3833-5f6d-be9b-c029cfefdfdf', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '205a81aa-6fcb-50de-9853-40623f88ea06', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 58, false),
      ('757a956e-5058-5d13-860b-0ce5122eb53d', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '205a81aa-6fcb-50de-9853-40623f88ea06', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 58, false),
      ('3e512eb2-63c8-5b1a-ae9c-e0b2e80d217f', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 58, false),
      ('d417f99a-2552-5a39-b432-40507c832836', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 58, false),
      ('901a3d50-8d2f-5b06-93da-52f42b530436', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', 3, 'Acrescente a margarina e sove até atingir o ponto de véu, esticando uma pequena porção até ficar transparente sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 58, false),
      ('76ffbedd-0e32-5595-afd2-50c69c05d0ee', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente. A massa é macia e pegajosa, e suas mãos precisam do óleo para mexer.', null, 58, false),
      ('e6418b3e-56bf-5efb-984e-c7a0bd75dd62', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', 5, 'Abra a massa em superfície untada com óleo e espalhe as gotas de chocolate; enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as gotas de chocolate. Enrole bem e modele formando uma bola', null, 58, false),
      ('24a3994d-b02c-579b-a4db-5dfff2184a96', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', 6, 'Coloque em uma tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 59, false),
      ('8cd28035-1553-5347-9769-a63d1157b7d4', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', 7, 'Volte para a superfície untada, divida em duas partes do mesmo tamanho e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 59, false),
      ('6fe06da4-a6ec-5fee-8a17-1f29bbef1fc9', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', 8, 'Aguarde a massa crescer até a borda e asse em forno preaquecido a 180 graus por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 59, false),
      ('9bcb2c06-fcf0-539a-9f96-9955701725e1', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '3c8f0fe4-cd35-5a21-b4e0-8ef3b63cdd06', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 59, false),
      ('365ea16e-cb71-5c07-87fa-7787c2c4531c', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '06aded77-6774-5767-bcc8-e04d6eb9df80', 1, 'Leve ao fogo médio, em panela de fundo grosso, o leite condensado, o creme de leite, o cacau e a manteiga.', 'Leve ao fogo médio, em panela de fundo grosso, o leite condensado, o creme de leite, o cacau e a manteiga.', null, 59, false),
      ('5880e328-a12d-5499-b789-aeaa3273871e', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', '06aded77-6774-5767-bcc8-e04d6eb9df80', 2, 'Mexa por 5 minutos; acrescente o chocolate meio amargo e continue mexendo até engrossar e começar a desgrudar do fundo. Deixe esfriar.', 'Mexa por 5 minutos; acrescente o chocolate meio amargo e continue mexendo até engrossar e começar a desgrudar do fundo. Deixe esfriar.', null, 60, false),
      ('b99f41d6-104c-59b3-a5af-e23386a558d3', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', 'e2bfa9ac-a34a-5a45-9c81-5ef24aa79e34', 1, 'Corte o topo do Chocotone e reserve.', 'Comece cortando o topo do Chocotone e reserve.', null, 59, false),
      ('6baf7314-f9bd-5021-a754-ac8f0916e46d', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', 'e2bfa9ac-a34a-5a45-9c81-5ef24aa79e34', 2, 'Abra uma cavidade com faca e colher, deixando um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Chocotone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Chocotone não perder a estrutura e quebrar).', null, 60, false),
      ('b747262f-ac85-5e88-bbc7-6247979f502f', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', 'e2bfa9ac-a34a-5a45-9c81-5ef24aa79e34', 3, 'Adicione o recheio com uma colher ou saco de confeitar.', 'Depois adicione o recheio com uma colher ou um saco de confeitar. Decore com brigadeiros.', null, 60, false),
      ('ce6a29ee-8b5a-537e-835c-fae7eca1a70d', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', 'e2bfa9ac-a34a-5a45-9c81-5ef24aa79e34', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa, quando indicado na receita.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 60, false),
      ('68a90e15-639b-5f38-9f86-6eb3ec8b7af0', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', 'e2bfa9ac-a34a-5a45-9c81-5ef24aa79e34', 5, 'Recoloque a tampa e finalize conforme a decoração indicada na receita.', 'Por último coloque a tampa do seu Panetone/Chocotone e decore da maneira de sua preferência, usando sua criatividade.', null, 60, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('2bd7cfbc-1d22-5f1a-ac01-659c3c33a290', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', 'natal'),
      ('83da800c-9d33-5d6f-9cb1-15ef6080d713', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', 'chocotone')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('b1eaa580-4a09-5015-a14f-dc226d6db970', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', null, 'recipe', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', 'yield', 'warning', 'A apostila informa rendimento de 5 unidades de 500g, mas também orienta dividir a massa em duas partes. Confirmar o rendimento na revisão.', 58),
      ('0bb40099-673a-5bd4-a371-fa6de4a41c13', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', null, 'recipe', 'ceb882d2-0dba-55b5-88d1-89c8e9991514', 'source_pages', 'warning', 'Paginação baseada na transcrição enviada; conferir no PDF original antes da publicação.', 57)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Chocotone de Brigadeiro
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38')
     and not exists (select 1 from public.recipe_steps where recipe_id = '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('b7c17d10-b431-5795-8214-4eab75bfba02', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', null, 'esponja', 'Esponja', null, null, 1, 1, 37, 38),
      ('1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', null, 'massa', 'Massa do Chocotone', null, null, 1, 2, 37, 38),
      ('a25fd565-e585-5c2b-8ea4-27f45eb242ee', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', null, 'recheio', 'Recheio de Brigadeiro', null, null, 1, 3, 39, 40),
      ('392a9d3d-bc3e-568a-b1d3-0b33a344d88c', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', null, 'montagem', 'Montagem — Chocotone de Brigadeiro', null, null, 1, 4, 39, 40)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('02bb3459-44e5-5c9f-9c8e-ff5524889372', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', 'b7c17d10-b431-5795-8214-4eab75bfba02', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 37, false),
      ('2cd8c794-021a-5646-9b19-d00f9e2ef72b', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', 'b7c17d10-b431-5795-8214-4eab75bfba02', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 37, false),
      ('7caa44bf-45c2-5b24-9252-c9bcf1469103', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', 'b7c17d10-b431-5795-8214-4eab75bfba02', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 37, false),
      ('af76508a-420d-5c1a-87d2-7303c7004274', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 37, false),
      ('6627aead-469e-5b60-b0b4-ab3b3198024d', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 37, false),
      ('c2de8595-514b-5c16-9a17-2d6cde751ad4', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', null, 3, 5, null, 'colheres (sopa)', null, 'Leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 37, false),
      ('4a976194-db10-5d49-b247-8eb265c05b57', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 37, false),
      ('bd60d19d-c78f-5e6e-96fb-560691b87918', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 37, false),
      ('4b65859c-8c42-5dc3-b581-450322973eb4', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 37, false),
      ('24670e9d-830c-55fb-8dc1-c568797f6ecf', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 37, false),
      ('fe0aa194-5ed9-5cf0-9f09-7a9d0c7c2dda', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 37, false),
      ('fd1d81b6-73ae-599a-9d8a-4d708397cd07', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 37, false),
      ('c8448faa-2a18-513d-856c-9b91617fd79c', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 37, false),
      ('f97ab94b-e2f7-55a9-a8ee-6ffa6c6cb49e', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 37, false),
      ('f12713bb-f092-50d0-a2f2-5702a5dc4edc', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', 'b9c850ce-e18b-58e0-aaa8-9dad5110b902', 12, 350, null, 'g', null, 'chocolate em gotas ou chocolate em barra picado', null, null, 'linear', false, '350g de chocolate em gotas ou chocolate em barra picado', 37, false),
      ('e81eee39-009f-5a4b-97f8-e9c1c1fed604', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', 'a25fd565-e585-5c2b-8ea4-27f45eb242ee', '6b34b876-9b3f-5612-96da-1abcf6f11bbc', 1, 1, null, 'unidade', null, 'leite condensado', null, null, 'linear', false, '1 leite condensado', 39, false),
      ('54830d22-d05b-5f98-8551-45ce2e286c8b', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', 'a25fd565-e585-5c2b-8ea4-27f45eb242ee', null, 2, 1, null, 'colher (café)', null, 'manteiga', null, null, 'linear', false, '1 colher (café) manteiga', 39, false),
      ('121c0924-474c-5919-b229-2a05958ac294', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', 'a25fd565-e585-5c2b-8ea4-27f45eb242ee', '8758d73e-4fcf-508e-940d-635708436a41', 3, 1, null, 'unidade', null, 'creme de leite', null, null, 'linear', false, '1 creme de leite', 39, false),
      ('6529ab0f-92e8-595f-94a5-99b01107687b', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', 'a25fd565-e585-5c2b-8ea4-27f45eb242ee', '298f0828-425b-5991-a12f-fdf8bb2fc461', 4, 50, null, 'g', null, 'cacau 50%', null, null, 'linear', false, '50g de cacau 50%', 39, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('757f81d9-ab02-5ab6-a9f3-dba7f4079c0c', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', 'b7c17d10-b431-5795-8214-4eab75bfba02', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 38, false),
      ('e80f30f7-3d69-59dd-9b96-7d604a0a8378', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', 'b7c17d10-b431-5795-8214-4eab75bfba02', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 38, false),
      ('0fad0f79-1ded-556d-9130-37fbfe48eb3f', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 38, false),
      ('2341c16d-a7d0-5a94-a74b-87039b950a08', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 38, false),
      ('f6cf51fa-d8bc-5adf-90d5-a59838991cdc', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', 3, 'Acrescente a margarina e sove até atingir o ponto de véu, esticando uma pequena porção até ficar transparente sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 38, false),
      ('5c2e0fc5-957a-5e19-93a9-29f336be9cbf', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente. A massa é macia e pegajosa, e suas mãos precisam do óleo para mexer.', null, 38, false),
      ('ae1682b4-31b0-5e1c-af19-40220c5e4322', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', 5, 'Abra a massa em superfície untada com óleo e espalhe as gotas de chocolate; enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as gotas de chocolate. Enrole bem e modele formando uma bola', null, 38, false),
      ('1c4ea411-d48b-5f12-80e7-277533a3d672', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', 6, 'Coloque em uma tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 39, false),
      ('de344c39-7625-5203-a302-319e7f08ac67', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', 7, 'Volte para a superfície untada, divida em duas partes do mesmo tamanho e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 39, false),
      ('18dd45c8-f31d-5e63-93b2-a50650c5ef75', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', 8, 'Aguarde a massa crescer até a borda e asse em forno preaquecido a 180 graus por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 39, false),
      ('df24481a-198e-5afd-a5cb-3fab0ecf13cb', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '1abec5f3-74c6-5cfb-86d8-fafd2b7dd7e1', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 39, false),
      ('cdd4c777-17c7-562c-9738-f9067853fb51', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', 'a25fd565-e585-5c2b-8ea4-27f45eb242ee', 1, 'Leve todos os ingredientes ao fogo em panela de fundo grosso.', 'Leve todos os ingredientes ao fogo em panela de fundo grosso.', null, 39, false),
      ('0bf64911-b2c2-5e09-ae89-5f5bc8832e3e', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', 'a25fd565-e585-5c2b-8ea4-27f45eb242ee', 2, 'Mexa até engrossar e começar a desgrudar do fundo da panela. Deixe esfriar em temperatura ambiente.', 'Mexa até engrossar e começar a desgrudar do fundo da panela. Deixe esfriar em temperatura ambiente.', null, 40, false),
      ('36597b72-f3b3-5f4d-abd0-c342ac6a6129', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '392a9d3d-bc3e-568a-b1d3-0b33a344d88c', 1, 'Corte o topo do Chocotone e reserve.', 'Comece cortando o topo do Chocotone e reserve.', null, 39, false),
      ('3a276880-4046-5aa7-978f-5eac1a49eb9f', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '392a9d3d-bc3e-568a-b1d3-0b33a344d88c', 2, 'Abra uma cavidade com faca e colher, deixando um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Chocotone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Chocotone não perder a estrutura e quebrar).', null, 40, false),
      ('6cf79b23-a0d6-5641-a402-32f1c392f000', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '392a9d3d-bc3e-568a-b1d3-0b33a344d88c', 3, 'Adicione o recheio com uma colher ou saco de confeitar.', 'Depois adicione o recheio com uma colher ou um saco de confeitar. Decore com raspas ou pedaços de chocolate, barras ou bombons.', null, 40, false),
      ('6f51b0fa-d009-5f41-811e-908d3711cb96', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '392a9d3d-bc3e-568a-b1d3-0b33a344d88c', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa, quando indicado na receita.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 40, false),
      ('8df082a7-68a3-536b-988e-69a1783ac02b', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', '392a9d3d-bc3e-568a-b1d3-0b33a344d88c', 5, 'Recoloque a tampa e finalize conforme a decoração indicada na receita.', 'Por último coloque a tampa do seu Panetone/Chocotone e decore da maneira de sua preferência, usando sua criatividade.', null, 40, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('a5f9483a-084b-5726-b833-e690751e6874', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', 'natal'),
      ('c784836f-a578-5740-8dbb-539003ae793a', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', 'chocotone')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('be54be08-2aa9-52f8-bdcc-b621b426eba3', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', null, 'recipe', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', 'yield', 'warning', 'A apostila informa rendimento de 5 unidades de 500g, mas também orienta dividir a massa em duas partes. Confirmar o rendimento na revisão.', 38),
      ('7268f2d2-18d9-5c80-a3e4-3958309ee4f9', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', null, 'recipe', '1b9fbb20-71a8-5675-a9d7-b1c2654e4d38', 'source_pages', 'warning', 'Paginação baseada na transcrição enviada; conferir no PDF original antes da publicação.', 37)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Chocotone de Churros
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be')
     and not exists (select 1 from public.recipe_steps where recipe_id = 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('a3e49b17-36d8-5331-bbf1-06e96ba02644', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', null, 'esponja', 'Esponja', null, null, 1, 1, 25, 26),
      ('3dfe2672-94a6-568b-8c5c-80a479ae362f', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', null, 'massa', 'Massa de Churros', null, null, 1, 2, 25, 27),
      ('c9ce2d4f-30dc-5a4a-a388-2251a598ba12', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', null, 'recheio', 'Recheio de Churros', null, null, 1, 3, 27, 27),
      ('cd863ec0-33cb-5087-90e4-de2f66c3c1ef', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', null, 'montagem', 'Montagem do Chocotone de Churros', null, null, 1, 4, 27, 27)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('e45bdbba-c631-5f2c-9944-41c616d53d17', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'a3e49b17-36d8-5331-bbf1-06e96ba02644', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 25, false),
      ('3f4a995d-c775-59eb-b6e8-0106dfaf5a4d', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'a3e49b17-36d8-5331-bbf1-06e96ba02644', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 25, false),
      ('0b2acc53-ea19-5984-a4c4-48e2f854f632', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'a3e49b17-36d8-5331-bbf1-06e96ba02644', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 25, false),
      ('d56a2cc3-4a28-5627-a122-cbf2282ec1dc', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 25, false),
      ('1e3c1f10-9db1-54e3-856a-28dca3714958', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 25, false),
      ('e982dbc7-1768-54a4-b632-dd57ff3d586b', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', '9b1e65ad-f9ce-50fa-aa1c-9d934b76e83c', 3, 5, null, 'colheres (sopa)', null, 'leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 25, false),
      ('906502d0-d263-525c-86d0-1be5a268dcd8', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 25, false),
      ('5a08cb01-cf17-5f0c-9cd5-1a5fd618cc9d', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', '66de60ad-556e-5d31-a00e-33e3d39f9b10', 5, 20, null, 'g', null, 'canela em pó', null, null, 'linear', false, '20g de canela em pó', 25, false),
      ('83163ba4-064e-587c-b58a-a3111a5578fc', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 6, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 25, false),
      ('80e5b30c-1d56-5145-8210-362edd783834', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', '0a718c08-62f3-5af3-8577-980614b5cf9d', 7, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 25, false),
      ('05cc22e6-d47a-53b6-a631-e3a3ee77c929', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 8, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 25, false),
      ('d874f7bf-d3ce-5a8a-828b-9c8f848eb247', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 9, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 25, false),
      ('2b1c1de7-fa13-554e-85e6-2cb1a86d2744', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 10, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 25, false),
      ('eedb7c62-8ec1-59da-8cf9-61af570898ea', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', '719de073-c900-5def-808b-af472a1c4be8', 11, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 25, false),
      ('b50d06d7-7d0c-5a9a-be65-94da445b50d8', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', null, 12, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 25, false),
      ('83581195-0211-54ab-a071-1de499908d75', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', null, 13, 350, null, 'g', null, 'chocolate em gotas ou chocolate em barra picado', null, null, 'linear', false, '350g de chocolate em gotas ou chocolate em barra picado', 25, false),
      ('6485eec6-fe23-5698-b112-e84a079b3930', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'c9ce2d4f-30dc-5a4a-a388-2251a598ba12', '6b34b876-9b3f-5612-96da-1abcf6f11bbc', 1, 1, null, 'unidade', null, 'leite condensado', null, null, 'linear', false, '1 leite condensado', 27, false),
      ('93879a18-a53d-5187-91e3-609dd73aeaec', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'c9ce2d4f-30dc-5a4a-a388-2251a598ba12', '8758d73e-4fcf-508e-940d-635708436a41', 2, 2, null, 'unidades', null, 'creme de leite', null, null, 'linear', false, '2 creme de leite', 27, false),
      ('5bee5980-8ba9-50c7-b429-95d3279eed45', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'c9ce2d4f-30dc-5a4a-a388-2251a598ba12', '66de60ad-556e-5d31-a00e-33e3d39f9b10', 3, 1, null, 'colher (café)', null, 'canela em pó', null, null, 'linear', false, '1 colher (café) canela em pó', 27, false),
      ('373c0008-06c3-5fc0-8781-bfbce50327b8', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'c9ce2d4f-30dc-5a4a-a388-2251a598ba12', 'd6023bf0-76f4-5247-899b-d967195f1018', 4, 200, null, 'g', null, 'doce de leite', null, null, 'linear', false, '200g de doce de leite', 27, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('5cd5766f-79e6-5509-a1ad-4bc7bd8cd6ae', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'a3e49b17-36d8-5331-bbf1-06e96ba02644', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 26, false),
      ('80d1153a-0be5-5e29-a5ae-78c608975b9a', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'a3e49b17-36d8-5331-bbf1-06e96ba02644', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 26, false),
      ('6cf923c0-b852-5d9d-8a0f-36364a0d65e1', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 26, false),
      ('970702bb-dc9a-546a-a5f2-72716e608235', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, a canela, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, a canela em pó, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 26, false),
      ('21945b7c-146e-515b-b73c-07c265d25dc8', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', 3, 'Acrescente a margarina e sove até atingir o ponto de véu.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 26, false),
      ('57dc7a2c-9944-5bb8-8312-ad6c085b62f7', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente.', null, 26, false),
      ('03a35f0c-c0c6-513c-8f8f-941710b4d00c', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', 5, 'Abra a massa em superfície untada com óleo, espalhe as gotas de chocolate, enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as gotas de chocolate. Enrole bem e modele formando uma bola', null, 26, false),
      ('fc3443c1-9d71-577d-8976-7118ad849a18', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', 6, 'Coloque em tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 27, false),
      ('5a7525b2-83ae-54c6-b8e3-44f807c94e56', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', 7, 'Divida a massa em duas partes iguais e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 27, false),
      ('b6590d33-da93-5ab7-9620-6be16629b7ee', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', 8, 'Aguarde crescer até a borda e asse em forno preaquecido a 180°C por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 27, false),
      ('8d7667e4-d6a9-5182-94c7-d719f5f4e090', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', '3dfe2672-94a6-568b-8c5c-80a479ae362f', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 27, false),
      ('3b938292-21b7-57df-bbd9-147057b5a452', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'c9ce2d4f-30dc-5a4a-a388-2251a598ba12', 1, 'Coloque todos os ingredientes em uma panela de fundo grosso e leve ao fogo médio, mexendo sem parar até o ponto de cobertura: ao levantar a colher ou espátula, a cobertura corre em fio reto.', 'Coloque todos os ingredientes em uma panela de fundo grosso e leve ao fogo médio, mecha sem parar até o ponto de cobertura, que é aquele ponto de fio reto, você levanta a colher ou espátula e a cobertura corre em fio reto.', null, 27, false),
      ('42a61786-a6fb-50d2-82f7-763b57b6f1b3', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'cd863ec0-33cb-5087-90e4-de2f66c3c1ef', 1, 'Corte o topo do Chocotone e reserve.', 'Comece cortando o topo do Chocotone e reserve.', null, 27, false),
      ('145cff32-f4a6-5465-bed4-2173a80ce839', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'cd863ec0-33cb-5087-90e4-de2f66c3c1ef', 2, 'Abra uma cavidade no Chocotone com a ajuda de uma faca e uma colher, deixando sempre um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Chocotone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Chocotone não perder a estrutura e quebrar).', null, 27, false),
      ('58ca14b7-a829-50bc-adbc-98168a318b3b', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'cd863ec0-33cb-5087-90e4-de2f66c3c1ef', 3, 'Adicione o recheio de Churros com uma colher ou um saco de confeitar.', 'Depois adicione o recheio de Churros com uma colher ou um saco de confeitar.', null, 27, false),
      ('25caf009-ea0f-5efc-8ba0-87ca00cb3e06', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'cd863ec0-33cb-5087-90e4-de2f66c3c1ef', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 27, false),
      ('3ea06252-c91d-5844-be9b-d46742069220', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'cd863ec0-33cb-5087-90e4-de2f66c3c1ef', 5, 'Coloque a tampa e decore com uma fita vermelha ou da maneira de sua preferência.', 'Por último coloque a tampa do seu Chocotone e decore com uma fita vermelha ou da maneira de sua preferência, usando sua criatividade.', null, 28, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('0843bd28-3d25-58d9-8f61-3d1dfc59e71b', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'natal'),
      ('7b05285c-2087-5ee9-8bf1-9ad82bdcbeca', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'chocotone'),
      ('94aace99-b371-58d1-9c40-fda6d90ca2e1', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'churros'),
      ('142eb18f-9724-53f7-974b-eb2f8cc1d888', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'canela')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('31baab20-511f-5890-8670-a3199d75eb40', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', null, 'recipe', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'yield', 'warning', 'O rendimento da massa é informado como 5 Chocotones de 500g; o recheio rende 1 Chocotone de 500g. A massa também orienta dividir em duas partes. Confirmar na revisão.', 27),
      ('bc99f3f6-c925-5a87-b5f2-e615e28dbfa6', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', null, 'recipe', 'f3f5c35a-3f46-5331-a0f0-00bca7fe63be', 'source_pages', 'warning', 'As páginas são as apresentadas na transcrição enviada nesta conversa; conferir a paginação no PDF original antes da publicação.', 25)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Chocotone de Coco
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2')
     and not exists (select 1 from public.recipe_steps where recipe_id = '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('bef16ebf-3e76-539c-9735-b22e9cc915e2', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', null, 'esponja', 'Esponja', null, null, 1, 1, 65, 66),
      ('42c8227d-0e6c-5ad4-87d3-fb92fae32476', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', null, 'massa', 'Massa do Chocotone', null, null, 1, 2, 65, 66),
      ('1164a4b3-0eb5-5b2b-93ad-9e190f7ca838', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', null, 'recheio', 'Recheio de Coco', null, null, 1, 3, 67, 68),
      ('9bd58c73-a88c-55c9-9985-88c530b69991', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', null, 'montagem', 'Montagem — Chocotone de Coco', null, null, 1, 4, 67, 68)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('0391a026-7062-50f0-96bd-761bdf8e2931', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', 'bef16ebf-3e76-539c-9735-b22e9cc915e2', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 65, false),
      ('918b4fde-9867-50db-8702-8257f3aeb140', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', 'bef16ebf-3e76-539c-9735-b22e9cc915e2', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 65, false),
      ('4f2245c1-aade-531f-8e34-0aa17fcf52a5', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', 'bef16ebf-3e76-539c-9735-b22e9cc915e2', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 65, false),
      ('6468389e-2fbe-5d92-97b9-252469e80966', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '42c8227d-0e6c-5ad4-87d3-fb92fae32476', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 65, false),
      ('7bf686b7-d288-5dfd-9299-f0680bc029ea', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '42c8227d-0e6c-5ad4-87d3-fb92fae32476', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 65, false),
      ('162e3c57-c15a-5f7f-a21c-d5b8c3fbbb3a', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '42c8227d-0e6c-5ad4-87d3-fb92fae32476', null, 3, 5, null, 'colheres (sopa)', null, 'Leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 65, false),
      ('528797ae-cbd7-524f-b42b-0f7be8daf1ff', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '42c8227d-0e6c-5ad4-87d3-fb92fae32476', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 65, false),
      ('d2f81784-c814-5279-87fe-cd53154281cc', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '42c8227d-0e6c-5ad4-87d3-fb92fae32476', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 65, false),
      ('a527b96c-0d38-54f8-8709-fc2b422e0211', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '42c8227d-0e6c-5ad4-87d3-fb92fae32476', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 65, false),
      ('59d7a748-1750-5345-89f0-20c9f636b54c', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '42c8227d-0e6c-5ad4-87d3-fb92fae32476', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 65, false),
      ('b4d363ce-49c5-55ca-8931-1194dcf305b0', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '42c8227d-0e6c-5ad4-87d3-fb92fae32476', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 65, false),
      ('2bdb85eb-cf1c-51ab-a628-53628ae1ae02', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '42c8227d-0e6c-5ad4-87d3-fb92fae32476', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 65, false),
      ('6bee7d4c-f47a-5825-a210-7ce66f8ab42e', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '42c8227d-0e6c-5ad4-87d3-fb92fae32476', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 65, false),
      ('f8bb69e5-273e-57cc-8dde-bcf92587b465', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '42c8227d-0e6c-5ad4-87d3-fb92fae32476', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 65, false),
      ('2ef9334e-d55e-526b-9b82-c1cd4b75cae5', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '42c8227d-0e6c-5ad4-87d3-fb92fae32476', 'b9c850ce-e18b-58e0-aaa8-9dad5110b902', 12, 350, null, 'g', null, 'chocolate em gotas ou chocolate em barra picado', null, null, 'linear', false, '350g de chocolate em gotas ou chocolate em barra picado', 65, false),
      ('693f4e83-e395-50cc-a0f6-527b0be807e1', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '1164a4b3-0eb5-5b2b-93ad-9e190f7ca838', '6b34b876-9b3f-5612-96da-1abcf6f11bbc', 1, 1, null, 'unidade', null, 'leite condensado', null, null, 'linear', false, '1 leite condensado', 67, false),
      ('bb5b2e12-6cf8-5109-8187-40dbf8c36924', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '1164a4b3-0eb5-5b2b-93ad-9e190f7ca838', null, 2, 100, null, 'ml', null, 'leite de coco ou creme de leite', null, null, 'linear', false, '100ml leite de coco ou creme de leite', 67, false),
      ('7a1ced59-0354-550b-9a8c-7b74d1decdad', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '1164a4b3-0eb5-5b2b-93ad-9e190f7ca838', null, 3, 150, null, 'g', null, 'coco ralado seco', null, null, 'linear', false, '150g coco ralado seco', 67, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('0dded705-3f08-573e-81f3-5afa22c4d51b', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', 'bef16ebf-3e76-539c-9735-b22e9cc915e2', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 66, false),
      ('b2bce75d-b486-531b-9e3a-797f7ea278bb', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', 'bef16ebf-3e76-539c-9735-b22e9cc915e2', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 66, false),
      ('478d0f2b-9258-5f99-93ee-d529bc54e472', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '42c8227d-0e6c-5ad4-87d3-fb92fae32476', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 66, false),
      ('ba4a4316-9c38-50e4-8876-6c9b2df9b431', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '42c8227d-0e6c-5ad4-87d3-fb92fae32476', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 66, false),
      ('edae5af9-4d75-5562-944b-e31f5171b430', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '42c8227d-0e6c-5ad4-87d3-fb92fae32476', 3, 'Acrescente a margarina e sove até atingir o ponto de véu, esticando uma pequena porção até ficar transparente sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 66, false),
      ('0df5b06a-e8fa-5c6e-8d06-111ca6e943f7', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '42c8227d-0e6c-5ad4-87d3-fb92fae32476', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente. A massa é macia e pegajosa, e suas mãos precisam do óleo para mexer.', null, 66, false),
      ('83a0c7d2-02f6-5acd-b59a-96e6a2b7a4b6', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '42c8227d-0e6c-5ad4-87d3-fb92fae32476', 5, 'Abra a massa em superfície untada com óleo e espalhe as gotas de chocolate; enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as gotas de chocolate. Enrole bem e modele formando uma bola', null, 66, false),
      ('f098dd6b-700e-58cc-8122-e936bba38c13', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '42c8227d-0e6c-5ad4-87d3-fb92fae32476', 6, 'Coloque em uma tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 67, false),
      ('18f64b18-7b23-5ce0-8ed7-b540bbdeb469', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '42c8227d-0e6c-5ad4-87d3-fb92fae32476', 7, 'Volte para a superfície untada, divida em duas partes do mesmo tamanho e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 67, false),
      ('b55fe0bd-5504-5009-9ec2-ec0af5304024', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '42c8227d-0e6c-5ad4-87d3-fb92fae32476', 8, 'Aguarde a massa crescer até a borda e asse em forno preaquecido a 180 graus por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 67, false),
      ('105f1825-51e6-59ef-a6c4-80ada05409b4', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '42c8227d-0e6c-5ad4-87d3-fb92fae32476', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 67, false),
      ('42b0081d-5a6a-55ba-ba6a-64901ff58f43', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '1164a4b3-0eb5-5b2b-93ad-9e190f7ca838', 1, 'Misture o coco ralado seco, o leite de coco e o leite condensado em panela de fundo grosso.', 'Misture o coco ralado seco, o leite de coco e o leite condensado em panela de fundo grosso.', null, 67, false),
      ('0a180133-f86a-5870-97ce-84b2a37e614e', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '1164a4b3-0eb5-5b2b-93ad-9e190f7ca838', 2, 'Leve ao fogo e mexa em movimentos circulares até engrossar e aparecer o fundo da panela. Deixe esfriar.', 'Leve ao fogo e mexa em movimentos circulares até engrossar e aparecer o fundo da panela. Deixe esfriar.', null, 68, false),
      ('b24cd503-71ec-5db1-95ff-4173900af261', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '9bd58c73-a88c-55c9-9985-88c530b69991', 1, 'Corte o topo do Chocotone e reserve.', 'Comece cortando o topo do Chocotone e reserve.', null, 67, false),
      ('f2867da2-a7e7-5405-ab18-c3239c211a81', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '9bd58c73-a88c-55c9-9985-88c530b69991', 2, 'Abra uma cavidade com faca e colher, deixando um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Chocotone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Chocotone não perder a estrutura e quebrar).', null, 68, false),
      ('1187ffc1-15b6-5fbc-b2c3-98c45fc32cfc', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '9bd58c73-a88c-55c9-9985-88c530b69991', 3, 'Adicione o recheio com uma colher ou saco de confeitar.', 'Depois adicione o recheio com uma colher ou um saco de confeitar. Decore com coco ralado.', null, 68, false),
      ('6800f269-95e8-551c-911c-d49f8c9e21e7', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '9bd58c73-a88c-55c9-9985-88c530b69991', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa, quando indicado na receita.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 68, false),
      ('eb2cf1f6-9046-5633-a14c-7d5abc1952d8', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', '9bd58c73-a88c-55c9-9985-88c530b69991', 5, 'Recoloque a tampa e finalize conforme a decoração indicada na receita.', 'Por último coloque a tampa do seu Panetone/Chocotone e decore da maneira de sua preferência, usando sua criatividade.', null, 68, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('009dd6d6-022e-5990-a0f7-d8025497a616', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', 'natal'),
      ('73c5b622-946c-55aa-9103-e136f02cd96d', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', 'chocotone')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('d19817ea-ced1-5542-9f09-11a5a84ceffb', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', null, 'recipe', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', 'yield', 'warning', 'A apostila informa rendimento de 5 unidades de 500g, mas também orienta dividir a massa em duas partes. Confirmar o rendimento na revisão.', 66),
      ('b34ef339-8063-5462-841f-26a9ff516522', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', null, 'recipe', '8e0079a6-c76a-5eeb-a5fb-5003bf6085a2', 'source_pages', 'warning', 'Paginação baseada na transcrição enviada; conferir no PDF original antes da publicação.', 65)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Chocotone de Ninho
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = 'f9435243-097a-5129-8c21-10874bac99c9')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = 'f9435243-097a-5129-8c21-10874bac99c9')
     and not exists (select 1 from public.recipe_steps where recipe_id = 'f9435243-097a-5129-8c21-10874bac99c9') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('843b5d30-7562-5820-bcd9-30843b501b60', 'f9435243-097a-5129-8c21-10874bac99c9', null, 'esponja', 'Esponja', null, null, 1, 1, 29, 30),
      ('af8c93fe-5076-53b2-89b8-791a4f2d7f67', 'f9435243-097a-5129-8c21-10874bac99c9', null, 'massa', 'Massa do Chocotone de Ninho', null, null, 1, 2, 29, 31),
      ('6b449755-18a3-5366-8537-c0c1833e574a', 'f9435243-097a-5129-8c21-10874bac99c9', null, 'recheio', 'Recheio de Ninho', null, null, 1, 3, 31, 32),
      ('9f497a6c-179a-5ff8-9d95-7bb49f145a48', 'f9435243-097a-5129-8c21-10874bac99c9', null, 'montagem', 'Montagem do Chocotone de Ninho', null, null, 1, 4, 32, 33)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('fa43edf6-3100-54f8-b2f6-84c80cc796cd', 'f9435243-097a-5129-8c21-10874bac99c9', '843b5d30-7562-5820-bcd9-30843b501b60', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 29, false),
      ('2a8a871f-ff42-5d39-b9ae-e2afd0d6e377', 'f9435243-097a-5129-8c21-10874bac99c9', '843b5d30-7562-5820-bcd9-30843b501b60', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 29, false),
      ('2d114cd9-62a6-573d-a4b3-e2e9e27aca17', 'f9435243-097a-5129-8c21-10874bac99c9', '843b5d30-7562-5820-bcd9-30843b501b60', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 29, false),
      ('46135d16-26b1-5e99-9bd1-befcafe3b42d', 'f9435243-097a-5129-8c21-10874bac99c9', 'af8c93fe-5076-53b2-89b8-791a4f2d7f67', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 29, false),
      ('1192680a-ace0-5fe8-a9f7-f91328fa45b8', 'f9435243-097a-5129-8c21-10874bac99c9', 'af8c93fe-5076-53b2-89b8-791a4f2d7f67', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 29, false),
      ('228ab4ab-c6a0-5de7-8727-e89babb946fd', 'f9435243-097a-5129-8c21-10874bac99c9', 'af8c93fe-5076-53b2-89b8-791a4f2d7f67', '9b1e65ad-f9ce-50fa-aa1c-9d934b76e83c', 3, 5, null, 'colheres (sopa)', null, 'leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 29, false),
      ('9612e960-e14b-50ca-8c79-c157029ac926', 'f9435243-097a-5129-8c21-10874bac99c9', 'af8c93fe-5076-53b2-89b8-791a4f2d7f67', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 29, false),
      ('f8fcba7f-60d2-5dd8-85d4-c4a926093224', 'f9435243-097a-5129-8c21-10874bac99c9', 'af8c93fe-5076-53b2-89b8-791a4f2d7f67', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 29, false),
      ('b8c3826e-4e32-5668-b99a-bc3b09ac4a6c', 'f9435243-097a-5129-8c21-10874bac99c9', 'af8c93fe-5076-53b2-89b8-791a4f2d7f67', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 29, false),
      ('725ca930-5589-52ef-8411-2fce3408694e', 'f9435243-097a-5129-8c21-10874bac99c9', 'af8c93fe-5076-53b2-89b8-791a4f2d7f67', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 29, false),
      ('ed039087-2194-5f3d-b627-f0c9d4512b61', 'f9435243-097a-5129-8c21-10874bac99c9', 'af8c93fe-5076-53b2-89b8-791a4f2d7f67', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 29, false),
      ('5a863ae9-e804-5e83-830f-c5e78d2bbb65', 'f9435243-097a-5129-8c21-10874bac99c9', 'af8c93fe-5076-53b2-89b8-791a4f2d7f67', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 29, false),
      ('94f15250-e195-5eb3-83c7-df8fb0cdd131', 'f9435243-097a-5129-8c21-10874bac99c9', 'af8c93fe-5076-53b2-89b8-791a4f2d7f67', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 29, false),
      ('5681d3d6-b5e5-5cfa-bffe-d0e68481a93f', 'f9435243-097a-5129-8c21-10874bac99c9', 'af8c93fe-5076-53b2-89b8-791a4f2d7f67', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 29, false),
      ('7cc1018b-ea0b-5702-b6c0-28c52b9701e7', 'f9435243-097a-5129-8c21-10874bac99c9', 'af8c93fe-5076-53b2-89b8-791a4f2d7f67', null, 12, 350, null, 'g', null, 'chocolate em gotas ou chocolate em barra picado', null, null, 'linear', false, '350g de chocolate em gotas ou chocolate em barra picado', 29, false),
      ('7b782b7d-013d-568f-9f83-09b6f2b30cc3', 'f9435243-097a-5129-8c21-10874bac99c9', '6b449755-18a3-5366-8537-c0c1833e574a', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 1, 2, null, 'unidades', null, 'gemas', null, null, 'linear', false, '2 gemas (passadas na peneira)', 31, false),
      ('dc0f7e5c-b329-5288-9f8f-e3718ea6b6c6', 'f9435243-097a-5129-8c21-10874bac99c9', '6b449755-18a3-5366-8537-c0c1833e574a', null, 2, 1, null, 'colher (sopa)', null, 'margarina ou manteiga', null, null, 'linear', false, '1 colher (sopa) margarina ou manteiga', 31, false),
      ('37f8c9d6-26b4-563e-b17c-66d6380eaffc', 'f9435243-097a-5129-8c21-10874bac99c9', '6b449755-18a3-5366-8537-c0c1833e574a', '6b34b876-9b3f-5612-96da-1abcf6f11bbc', 3, 2, null, 'unidades', null, 'leite condensado', null, null, 'linear', false, '2 leite condensado', 31, false),
      ('cedb385c-b205-59fe-90c6-298c78630855', 'f9435243-097a-5129-8c21-10874bac99c9', '6b449755-18a3-5366-8537-c0c1833e574a', '9b1e65ad-f9ce-50fa-aa1c-9d934b76e83c', 4, 1, null, 'xícara (240ml)', null, 'leite Ninho', null, null, 'linear', false, '1 xícara (240ml) leite ninho', 31, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('f9e138cc-e753-5a9a-a840-b503ed2ad972', 'f9435243-097a-5129-8c21-10874bac99c9', '843b5d30-7562-5820-bcd9-30843b501b60', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 30, false),
      ('86fadb76-6277-5f0f-8f48-74b3146bbb63', 'f9435243-097a-5129-8c21-10874bac99c9', '843b5d30-7562-5820-bcd9-30843b501b60', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 30, false),
      ('83619227-f12f-58fb-b518-639080bb7130', 'f9435243-097a-5129-8c21-10874bac99c9', 'af8c93fe-5076-53b2-89b8-791a4f2d7f67', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 30, false),
      ('af3ed4ac-436c-524a-84d5-0cc78125d023', 'f9435243-097a-5129-8c21-10874bac99c9', 'af8c93fe-5076-53b2-89b8-791a4f2d7f67', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 30, false),
      ('3c37ad12-2b63-5369-98d0-f73b1664da72', 'f9435243-097a-5129-8c21-10874bac99c9', 'af8c93fe-5076-53b2-89b8-791a4f2d7f67', 3, 'Acrescente a margarina e sove até atingir o ponto de véu.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 30, false),
      ('4cfe4633-71d9-5a5c-95df-49dcabe91e4d', 'f9435243-097a-5129-8c21-10874bac99c9', 'af8c93fe-5076-53b2-89b8-791a4f2d7f67', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente.', null, 30, false),
      ('fbb04646-e0f7-5598-b94d-0a8c95a7f512', 'f9435243-097a-5129-8c21-10874bac99c9', 'af8c93fe-5076-53b2-89b8-791a4f2d7f67', 5, 'Abra a massa em superfície untada com óleo, espalhe as gotas de chocolate, enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as gotas de chocolate. Enrole bem e modele formando uma bola', null, 30, false),
      ('c760f415-0d06-5680-ad2d-20745d3f259c', 'f9435243-097a-5129-8c21-10874bac99c9', 'af8c93fe-5076-53b2-89b8-791a4f2d7f67', 6, 'Coloque em tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 31, false),
      ('8ae3208a-7036-5abb-bd41-8f25e912bab8', 'f9435243-097a-5129-8c21-10874bac99c9', 'af8c93fe-5076-53b2-89b8-791a4f2d7f67', 7, 'Divida a massa em duas partes iguais e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 31, false),
      ('bdc46052-febe-545a-926b-e0faf4f22b35', 'f9435243-097a-5129-8c21-10874bac99c9', 'af8c93fe-5076-53b2-89b8-791a4f2d7f67', 8, 'Aguarde crescer até a borda e asse em forno preaquecido a 180°C por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 31, false),
      ('23ae821c-4ec8-5be7-827f-0726cb902b5f', 'f9435243-097a-5129-8c21-10874bac99c9', 'af8c93fe-5076-53b2-89b8-791a4f2d7f67', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 31, false),
      ('17bf8665-bdb1-58ac-87b5-22f1e2614233', 'f9435243-097a-5129-8c21-10874bac99c9', '6b449755-18a3-5366-8537-c0c1833e574a', 1, 'Coloque todos os ingredientes em uma panela e leve ao fogo baixo, mexendo sempre até engrossar.', 'Coloque todos os ingredientes em uma panela e leve ao fogo, mexendo sempre em fogo baixo até engrossar.', null, 32, false),
      ('99e60ef5-640a-543a-bc77-55ca2945432b', 'f9435243-097a-5129-8c21-10874bac99c9', '6b449755-18a3-5366-8537-c0c1833e574a', 2, 'Quando estiver frio, leve à geladeira ou deixe esfriar completamente em temperatura ambiente. Use para rechear e cobrir o topo do Chocotone.', 'Depois leve à geladeira quando estiver frio ou deixe esfriar por completo em temperatura ambiente. Pronto... Já pode usar para rechear e cobrir o topo do seu Chocotone.', null, 32, false),
      ('3187aa30-a0e5-59d6-856a-d22f71999198', 'f9435243-097a-5129-8c21-10874bac99c9', '9f497a6c-179a-5ff8-9d95-7bb49f145a48', 1, 'Corte o topo do Chocotone e reserve.', 'Comece cortando o topo do Chocotone e reserve.', null, 32, false),
      ('9894afb2-de39-5960-9bcb-74e51eb26135', 'f9435243-097a-5129-8c21-10874bac99c9', '9f497a6c-179a-5ff8-9d95-7bb49f145a48', 2, 'Abra uma cavidade no Chocotone com faca e colher, deixando um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Chocotone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Chocotone não perder a estrutura e quebrar).', null, 32, false),
      ('15544eaa-9152-5e6c-9086-d5790e6293a3', 'f9435243-097a-5129-8c21-10874bac99c9', '9f497a6c-179a-5ff8-9d95-7bb49f145a48', 3, 'Adicione o recheio de Ninho com uma colher ou saco de confeitar.', 'Depois adicione o recheio de Ninho com uma colher ou um saco de confeitar.', null, 32, false),
      ('7af1d450-86bb-5f6a-b4e9-edfbcf2254e1', 'f9435243-097a-5129-8c21-10874bac99c9', '9f497a6c-179a-5ff8-9d95-7bb49f145a48', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 32, false),
      ('8acad48f-ad13-5752-bbde-a4c957800866', 'f9435243-097a-5129-8c21-10874bac99c9', '9f497a6c-179a-5ff8-9d95-7bb49f145a48', 5, 'Coloque a tampa, passe um pouco do recheio por cima e decore.', 'Por último coloque a tampa do seu Chocotone e passe um pouco do recheio em cima e decore com uma fita vermelha ou da maneira de sua preferência, usando sua criatividade.', null, 33, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('3a215871-70af-5753-9695-58312b2683bb', 'f9435243-097a-5129-8c21-10874bac99c9', 'natal'),
      ('ade29668-0660-56e3-8017-e22358e8d9aa', 'f9435243-097a-5129-8c21-10874bac99c9', 'chocotone'),
      ('112db378-4fc8-5eea-8663-77a6c706d118', 'f9435243-097a-5129-8c21-10874bac99c9', 'leite-em-po')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('43a5ab3f-d80b-5c0c-8cd0-a1fce92945ae', 'f9435243-097a-5129-8c21-10874bac99c9', null, 'recipe', 'f9435243-097a-5129-8c21-10874bac99c9', 'yield', 'warning', 'O rendimento da massa é informado como 5 Chocotones de 500g; o recheio rende 1 Chocotone de 500g. A massa também orienta dividir em duas partes. Confirmar na revisão.', 31),
      ('61e1bb50-6fb6-55dd-b623-aa37b0952504', 'f9435243-097a-5129-8c21-10874bac99c9', null, 'recipe', 'f9435243-097a-5129-8c21-10874bac99c9', 'source_pages', 'warning', 'As páginas são as apresentadas na transcrição enviada nesta conversa; conferir a paginação no PDF original antes da publicação.', 29)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Chocotone de Nutella
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = '3e9a4b0a-d7f0-5047-ac81-784a3e737d71')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = '3e9a4b0a-d7f0-5047-ac81-784a3e737d71')
     and not exists (select 1 from public.recipe_steps where recipe_id = '3e9a4b0a-d7f0-5047-ac81-784a3e737d71') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('1c016ff5-3f7a-5074-9a85-04aaab8b3b68', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', null, 'esponja', 'Esponja', null, null, 1, 1, 61, 62),
      ('276238ef-7b9e-514f-aea3-58ec75899f27', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', null, 'massa', 'Massa do Chocotone', null, null, 1, 2, 61, 62),
      ('301257c9-0cea-5df6-bdd2-4430af87ec95', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', null, 'recheio', 'Recheio de Nutella', null, null, 1, 3, 63, 64),
      ('2e20e9b9-7ae9-5887-b849-190f60719071', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', null, 'montagem', 'Montagem — Chocotone de Nutella', null, null, 1, 4, 63, 64)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('9506bac1-8289-5b4e-8f03-1762f216c6e4', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '1c016ff5-3f7a-5074-9a85-04aaab8b3b68', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 61, false),
      ('a5f7dccb-7ab1-513a-9dbb-14e3431197e7', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '1c016ff5-3f7a-5074-9a85-04aaab8b3b68', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 61, false),
      ('94dfb2ee-f0ea-532e-bfcd-ad22d6c504f5', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '1c016ff5-3f7a-5074-9a85-04aaab8b3b68', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 61, false),
      ('288da139-c627-5f36-866c-be231dd5523a', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '276238ef-7b9e-514f-aea3-58ec75899f27', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 61, false),
      ('ea8f41f0-7461-504d-bc5d-6dfa857ab4e1', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '276238ef-7b9e-514f-aea3-58ec75899f27', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 61, false),
      ('de27f5eb-f979-530c-96fd-dbbadf5beaec', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '276238ef-7b9e-514f-aea3-58ec75899f27', null, 3, 5, null, 'colheres (sopa)', null, 'Leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 61, false),
      ('ef6912a4-0bc8-50af-b24d-6f142b03ef1f', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '276238ef-7b9e-514f-aea3-58ec75899f27', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 61, false),
      ('e689b29f-a3b4-5b58-8eaa-3cfd600213c3', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '276238ef-7b9e-514f-aea3-58ec75899f27', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 61, false),
      ('9962e1f2-a009-5299-aba1-a4a7623ce70b', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '276238ef-7b9e-514f-aea3-58ec75899f27', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 61, false),
      ('2ac32e6b-f144-57f4-b151-74e8edc65e55', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '276238ef-7b9e-514f-aea3-58ec75899f27', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 61, false),
      ('920eda32-632d-5198-adf4-4330351f9148', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '276238ef-7b9e-514f-aea3-58ec75899f27', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 61, false),
      ('66272581-aac9-5d4a-a1e5-b02850a3a34e', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '276238ef-7b9e-514f-aea3-58ec75899f27', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 61, false),
      ('47813838-e3c0-513a-a537-868db8d2b569', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '276238ef-7b9e-514f-aea3-58ec75899f27', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 61, false),
      ('a1c9e10f-a8a2-5a86-8a56-51f6a8f19599', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '276238ef-7b9e-514f-aea3-58ec75899f27', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 61, false),
      ('7fb07c40-d5f3-502a-9b7d-be39468d7bf0', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '276238ef-7b9e-514f-aea3-58ec75899f27', 'b9c850ce-e18b-58e0-aaa8-9dad5110b902', 12, 350, null, 'g', null, 'chocolate em gotas ou chocolate em barra picado', null, null, 'linear', false, '350g de chocolate em gotas ou chocolate em barra picado', 61, false),
      ('5b190312-9b14-5acc-8e89-8d43558bdf14', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '301257c9-0cea-5df6-bdd2-4430af87ec95', '562bc70c-661f-5b07-8a95-eb8378d53841', 1, 250, null, 'g', null, 'Nutella', null, null, 'linear', false, '250g de nutella', 63, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('7a4d0838-7236-5c4e-aeed-9139ee021a24', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '1c016ff5-3f7a-5074-9a85-04aaab8b3b68', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 62, false),
      ('8ee40cd9-75b4-592a-afde-688fa554cb22', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '1c016ff5-3f7a-5074-9a85-04aaab8b3b68', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 62, false),
      ('febbbb07-11dc-5e63-9201-0155b29decce', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '276238ef-7b9e-514f-aea3-58ec75899f27', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 62, false),
      ('66f301f7-b5bd-5645-a218-3c1834c4152c', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '276238ef-7b9e-514f-aea3-58ec75899f27', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 62, false),
      ('22dd9f04-b33a-575c-ba93-9333f31b938a', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '276238ef-7b9e-514f-aea3-58ec75899f27', 3, 'Acrescente a margarina e sove até atingir o ponto de véu, esticando uma pequena porção até ficar transparente sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 62, false),
      ('56c92ff7-867c-5564-b238-f1451d58a7b5', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '276238ef-7b9e-514f-aea3-58ec75899f27', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente. A massa é macia e pegajosa, e suas mãos precisam do óleo para mexer.', null, 62, false),
      ('0237b72f-807e-5568-9e9f-7aae617dd91f', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '276238ef-7b9e-514f-aea3-58ec75899f27', 5, 'Abra a massa em superfície untada com óleo e espalhe as gotas de chocolate; enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as gotas de chocolate. Enrole bem e modele formando uma bola', null, 62, false),
      ('a1c6d10b-df6c-56fc-9da3-43d2ed16b2b1', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '276238ef-7b9e-514f-aea3-58ec75899f27', 6, 'Coloque em uma tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 63, false),
      ('1116c413-de65-5d64-b706-6c7e994a7c63', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '276238ef-7b9e-514f-aea3-58ec75899f27', 7, 'Volte para a superfície untada, divida em duas partes do mesmo tamanho e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 63, false),
      ('f14b0478-7e3a-59b4-b811-fbeb415c17cc', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '276238ef-7b9e-514f-aea3-58ec75899f27', 8, 'Aguarde a massa crescer até a borda e asse em forno preaquecido a 180 graus por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 63, false),
      ('995b76ce-3888-5f9c-9fbe-bab5d4d28104', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '276238ef-7b9e-514f-aea3-58ec75899f27', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 63, false),
      ('b033111c-1e3b-5acd-81b0-35310fe19ea2', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '301257c9-0cea-5df6-bdd2-4430af87ec95', 1, 'A receita indica utilizar 250g de Nutella; não há preparo adicional descrito.', 'A receita indica utilizar 250g de Nutella; não há preparo adicional descrito.', null, 63, false),
      ('951fd154-1619-532a-8dbd-cafcc03ff4f1', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '2e20e9b9-7ae9-5887-b849-190f60719071', 1, 'Corte o topo do Chocotone e reserve.', 'Comece cortando o topo do Chocotone e reserve.', null, 63, false),
      ('41ae8cbc-605f-51cf-bfe6-d025d7cda265', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '2e20e9b9-7ae9-5887-b849-190f60719071', 2, 'Abra uma cavidade com faca e colher, deixando um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Chocotone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Chocotone não perder a estrutura e quebrar).', null, 64, false),
      ('83d2c2b4-0e8b-5af7-a9c8-3975d9392b75', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '2e20e9b9-7ae9-5887-b849-190f60719071', 3, 'Adicione o recheio com uma colher ou saco de confeitar.', 'Depois adicione o recheio com uma colher ou um saco de confeitar. Passe um pouco de Nutella sobre a tampa e decore com uma fita vermelha na lateral ou a gosto.', null, 64, false),
      ('69ef9158-cf33-51e9-aeb8-69a84fc32a21', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '2e20e9b9-7ae9-5887-b849-190f60719071', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa, quando indicado na receita.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 64, false),
      ('0001150c-fba3-5fa3-82a3-aa4147c7bfe2', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', '2e20e9b9-7ae9-5887-b849-190f60719071', 5, 'Recoloque a tampa e finalize conforme a decoração indicada na receita.', 'Por último coloque a tampa do seu Panetone/Chocotone e decore da maneira de sua preferência, usando sua criatividade.', null, 64, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('ba577aca-e018-5bb5-8059-8b7c4edf26a9', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', 'natal'),
      ('a8f77c14-a17d-5106-9bf5-e579a7213225', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', 'chocotone')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('f8019e93-8eea-535d-8356-724dbde502a9', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', null, 'recipe', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', 'yield', 'warning', 'A apostila informa rendimento de 5 unidades de 500g, mas também orienta dividir a massa em duas partes. Confirmar o rendimento na revisão.', 62),
      ('a0f10988-0685-530a-991f-0aa4bc7a082d', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', null, 'recipe', '3e9a4b0a-d7f0-5047-ac81-784a3e737d71', 'source_pages', 'warning', 'Paginação baseada na transcrição enviada; conferir no PDF original antes da publicação.', 61)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Chocotone de Oreo
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = '402d03c4-696f-5a06-bc57-60887ac4e688')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = '402d03c4-696f-5a06-bc57-60887ac4e688')
     and not exists (select 1 from public.recipe_steps where recipe_id = '402d03c4-696f-5a06-bc57-60887ac4e688') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('3e6d8332-7fd5-526c-895c-39fb33854c6d', '402d03c4-696f-5a06-bc57-60887ac4e688', null, 'esponja', 'Esponja', null, null, 1, 1, 69, 70),
      ('521019f3-c38d-536d-8727-d9fa6c794027', '402d03c4-696f-5a06-bc57-60887ac4e688', null, 'massa', 'Massa do Chocotone', null, null, 1, 2, 69, 70),
      ('944a1ae8-56d0-5acf-91cf-73699f683e94', '402d03c4-696f-5a06-bc57-60887ac4e688', null, 'recheio', 'Recheio de Oreo', null, null, 1, 3, 71, 72),
      ('95434fbd-ac49-53c3-a3a6-a20de98f5ed4', '402d03c4-696f-5a06-bc57-60887ac4e688', null, 'montagem', 'Montagem — Chocotone de Oreo', null, null, 1, 4, 71, 72)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('3ab5ac5d-a24f-59c5-aa64-01a7359c1c3b', '402d03c4-696f-5a06-bc57-60887ac4e688', '3e6d8332-7fd5-526c-895c-39fb33854c6d', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 69, false),
      ('04e6357a-b776-5d1f-9d82-87d40a66b4ab', '402d03c4-696f-5a06-bc57-60887ac4e688', '3e6d8332-7fd5-526c-895c-39fb33854c6d', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 69, false),
      ('53b0dc4d-13f9-5b85-87bf-1c3442a1966c', '402d03c4-696f-5a06-bc57-60887ac4e688', '3e6d8332-7fd5-526c-895c-39fb33854c6d', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 69, false),
      ('1753a7f3-ac61-5836-8023-8494be3f2469', '402d03c4-696f-5a06-bc57-60887ac4e688', '521019f3-c38d-536d-8727-d9fa6c794027', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 69, false),
      ('85375ba1-4c9a-5301-988b-18932ccb16b1', '402d03c4-696f-5a06-bc57-60887ac4e688', '521019f3-c38d-536d-8727-d9fa6c794027', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 69, false),
      ('83d03219-8472-578a-bf88-45b1747d6d56', '402d03c4-696f-5a06-bc57-60887ac4e688', '521019f3-c38d-536d-8727-d9fa6c794027', null, 3, 5, null, 'colheres (sopa)', null, 'Leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 69, false),
      ('25070437-a0d9-5dfb-9c76-ff446394eafe', '402d03c4-696f-5a06-bc57-60887ac4e688', '521019f3-c38d-536d-8727-d9fa6c794027', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 69, false),
      ('e9bc3819-3ef1-59a2-b1bf-f80c9f89bf0d', '402d03c4-696f-5a06-bc57-60887ac4e688', '521019f3-c38d-536d-8727-d9fa6c794027', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 69, false),
      ('cfe5d514-7f10-5cc0-ad03-4433948c3c4b', '402d03c4-696f-5a06-bc57-60887ac4e688', '521019f3-c38d-536d-8727-d9fa6c794027', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 69, false),
      ('150bfab4-24a3-5a76-85e9-882cb4490b04', '402d03c4-696f-5a06-bc57-60887ac4e688', '521019f3-c38d-536d-8727-d9fa6c794027', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 69, false),
      ('1c721366-b826-5d28-9be0-cb4d491279ac', '402d03c4-696f-5a06-bc57-60887ac4e688', '521019f3-c38d-536d-8727-d9fa6c794027', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 69, false),
      ('005bc17e-56be-5626-9a29-148442a014bc', '402d03c4-696f-5a06-bc57-60887ac4e688', '521019f3-c38d-536d-8727-d9fa6c794027', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 69, false),
      ('402e0029-37cc-5332-9648-ef47732a655b', '402d03c4-696f-5a06-bc57-60887ac4e688', '521019f3-c38d-536d-8727-d9fa6c794027', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 69, false),
      ('c48709b1-0e55-569f-af78-c58d4ccbc61f', '402d03c4-696f-5a06-bc57-60887ac4e688', '521019f3-c38d-536d-8727-d9fa6c794027', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 69, false),
      ('257d742f-307d-5af9-abb5-1fd21515e104', '402d03c4-696f-5a06-bc57-60887ac4e688', '521019f3-c38d-536d-8727-d9fa6c794027', 'b9c850ce-e18b-58e0-aaa8-9dad5110b902', 12, 350, null, 'g', null, 'chocolate em gotas ou chocolate em barra picado', null, null, 'linear', false, '350g de chocolate em gotas ou chocolate em barra picado', 69, false),
      ('d69ec3f2-d6e7-56b9-80b4-5f77d3ad47fb', '402d03c4-696f-5a06-bc57-60887ac4e688', '944a1ae8-56d0-5acf-91cf-73699f683e94', '6b34b876-9b3f-5612-96da-1abcf6f11bbc', 1, 1, null, 'unidade', null, 'leite condensado', null, null, 'linear', false, '1 leite condensado', 71, false),
      ('3f4bc68e-3c4e-5cd8-96f5-354dd432a2ad', '402d03c4-696f-5a06-bc57-60887ac4e688', '944a1ae8-56d0-5acf-91cf-73699f683e94', '8758d73e-4fcf-508e-940d-635708436a41', 2, 1, null, 'unidade', null, 'creme de leite', null, null, 'linear', false, '1 creme de leite', 71, false),
      ('84829547-b228-5869-b04f-45a72b11ad69', '402d03c4-696f-5a06-bc57-60887ac4e688', '944a1ae8-56d0-5acf-91cf-73699f683e94', null, 3, 50, null, 'g', null, 'bolacha Oreo sem recheio', null, null, 'linear', false, '50g de bolacha Oreo sem recheio', 71, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('f4b8c2a9-7212-56c7-8fa4-2f2751374ed9', '402d03c4-696f-5a06-bc57-60887ac4e688', '3e6d8332-7fd5-526c-895c-39fb33854c6d', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 70, false),
      ('6b661851-7980-54f0-b7de-e85a104af75d', '402d03c4-696f-5a06-bc57-60887ac4e688', '3e6d8332-7fd5-526c-895c-39fb33854c6d', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 70, false),
      ('0865f5cb-ddaf-531e-b08b-95c153cacaa1', '402d03c4-696f-5a06-bc57-60887ac4e688', '521019f3-c38d-536d-8727-d9fa6c794027', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 70, false),
      ('98adad1a-9679-54af-b931-6c3fbe2afde0', '402d03c4-696f-5a06-bc57-60887ac4e688', '521019f3-c38d-536d-8727-d9fa6c794027', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 70, false),
      ('89f2142f-6b19-53b5-8609-c924ac1148f6', '402d03c4-696f-5a06-bc57-60887ac4e688', '521019f3-c38d-536d-8727-d9fa6c794027', 3, 'Acrescente a margarina e sove até atingir o ponto de véu, esticando uma pequena porção até ficar transparente sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 70, false),
      ('8e433ada-9fe5-5dcc-b803-f07aefa82aca', '402d03c4-696f-5a06-bc57-60887ac4e688', '521019f3-c38d-536d-8727-d9fa6c794027', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente. A massa é macia e pegajosa, e suas mãos precisam do óleo para mexer.', null, 70, false),
      ('47058f4b-d9e6-5f63-aec8-67db5209f33b', '402d03c4-696f-5a06-bc57-60887ac4e688', '521019f3-c38d-536d-8727-d9fa6c794027', 5, 'Abra a massa em superfície untada com óleo e espalhe as gotas de chocolate; enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as gotas de chocolate. Enrole bem e modele formando uma bola', null, 70, false),
      ('8a8bb73e-65de-5220-a560-b53ca4dca284', '402d03c4-696f-5a06-bc57-60887ac4e688', '521019f3-c38d-536d-8727-d9fa6c794027', 6, 'Coloque em uma tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 71, false),
      ('1ed17c3c-e58b-59c9-a911-975deee78d53', '402d03c4-696f-5a06-bc57-60887ac4e688', '521019f3-c38d-536d-8727-d9fa6c794027', 7, 'Volte para a superfície untada, divida em duas partes do mesmo tamanho e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 71, false),
      ('2f0f208b-e4eb-5748-9b6f-1914e57aeb42', '402d03c4-696f-5a06-bc57-60887ac4e688', '521019f3-c38d-536d-8727-d9fa6c794027', 8, 'Aguarde a massa crescer até a borda e asse em forno preaquecido a 180 graus por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 71, false),
      ('198f1a77-cd02-5d5e-a165-3d27486e97e3', '402d03c4-696f-5a06-bc57-60887ac4e688', '521019f3-c38d-536d-8727-d9fa6c794027', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 71, false),
      ('e61cb350-72e2-5ba7-806d-bdce8bdc587a', '402d03c4-696f-5a06-bc57-60887ac4e688', '944a1ae8-56d0-5acf-91cf-73699f683e94', 1, 'Misture o leite condensado e o creme de leite em panela de fundo grosso.', 'Misture o leite condensado e o creme de leite em panela de fundo grosso.', null, 71, false),
      ('047782d9-469e-5fa7-92d6-a7681beb9274', '402d03c4-696f-5a06-bc57-60887ac4e688', '944a1ae8-56d0-5acf-91cf-73699f683e94', 2, 'Leve ao fogo e mexa em movimentos circulares até engrossar e aparecer o fundo da panela.', 'Leve ao fogo e mexa em movimentos circulares até engrossar e aparecer o fundo da panela.', null, 72, false),
      ('b0aa0a7e-7d3e-59c5-9daa-c285d5ac02c4', '402d03c4-696f-5a06-bc57-60887ac4e688', '944a1ae8-56d0-5acf-91cf-73699f683e94', 3, 'Deixe esfriar por completo e acrescente a bolacha Oreo picada.', 'Deixe esfriar por completo e acrescente a bolacha Oreo picada.', null, 72, false),
      ('3ad7b85f-5044-5db2-b5a3-749a776839c4', '402d03c4-696f-5a06-bc57-60887ac4e688', '95434fbd-ac49-53c3-a3a6-a20de98f5ed4', 1, 'Corte o topo do Chocotone e reserve.', 'Comece cortando o topo do Chocotone e reserve.', null, 71, false),
      ('29083a0a-21b7-53ac-bd6e-bfdd51a8d683', '402d03c4-696f-5a06-bc57-60887ac4e688', '95434fbd-ac49-53c3-a3a6-a20de98f5ed4', 2, 'Abra uma cavidade com faca e colher, deixando um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Chocotone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Chocotone não perder a estrutura e quebrar).', null, 72, false),
      ('83f6bd4c-57bd-5ffa-aee9-85bc4489983e', '402d03c4-696f-5a06-bc57-60887ac4e688', '95434fbd-ac49-53c3-a3a6-a20de98f5ed4', 3, 'Adicione o recheio com uma colher ou saco de confeitar.', 'Depois adicione o recheio com uma colher ou um saco de confeitar. A cobertura descrita é preparada com leite condensado, creme de leite e 50g de cacau 50%, cozidos até engrossar; espalhe sobre o topo e decore com biscoitos Oreo. As quantidades da cobertura não repetem a lista de ingredientes no trecho; conferir na revisão.', null, 72, false),
      ('7629d09d-ad43-5543-9e5f-acd4cc1d8c4b', '402d03c4-696f-5a06-bc57-60887ac4e688', '95434fbd-ac49-53c3-a3a6-a20de98f5ed4', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa, quando indicado na receita.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 72, false),
      ('3f51d908-5967-5b38-b0a3-dcc8e1fa7a26', '402d03c4-696f-5a06-bc57-60887ac4e688', '95434fbd-ac49-53c3-a3a6-a20de98f5ed4', 5, 'Recoloque a tampa e finalize conforme a decoração indicada na receita.', 'Por último coloque a tampa do seu Panetone/Chocotone e decore da maneira de sua preferência, usando sua criatividade.', null, 72, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('c1ac66f4-ec0e-5f34-aea8-8b05bfb91f3e', '402d03c4-696f-5a06-bc57-60887ac4e688', 'natal'),
      ('6238c4fd-ec16-57f3-bf97-69465d6ce57d', '402d03c4-696f-5a06-bc57-60887ac4e688', 'chocotone')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('bdafae85-5bbb-58d5-bb5d-94b3f0946a7c', '402d03c4-696f-5a06-bc57-60887ac4e688', null, 'recipe', '402d03c4-696f-5a06-bc57-60887ac4e688', 'yield', 'warning', 'A apostila informa rendimento de 5 unidades de 500g, mas também orienta dividir a massa em duas partes. Confirmar o rendimento na revisão.', 70),
      ('4aeb15f7-37cb-58ec-80cb-84efe52d9f87', '402d03c4-696f-5a06-bc57-60887ac4e688', null, 'recipe', '402d03c4-696f-5a06-bc57-60887ac4e688', 'source_pages', 'warning', 'Paginação baseada na transcrição enviada; conferir no PDF original antes da publicação.', 69)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Chocotone Dressed
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = '3ca180c0-e1e0-5205-b6f3-62d946e670fa')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = '3ca180c0-e1e0-5205-b6f3-62d946e670fa')
     and not exists (select 1 from public.recipe_steps where recipe_id = '3ca180c0-e1e0-5205-b6f3-62d946e670fa') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('7ebdda22-51a3-5d5a-89ad-bdb805661263', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', null, 'esponja', 'Esponja', null, null, 1, 1, 93, 94),
      ('e073a6db-61f8-5805-ba9d-8edfe3e980f4', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', null, 'massa', 'Massa do Chocotone', null, null, 1, 2, 93, 94),
      ('f8b52580-ebcb-5a79-8be8-bfceaacbccbc', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', null, 'recheio', 'Montagem com placa de textura', null, null, 1, 3, 95, 96),
      ('89c7fb6f-6c35-5879-9a5d-55666f897ef3', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', null, 'montagem', 'Montagem — Chocotone Dressed', null, null, 1, 4, 95, 96)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('f7419e58-a060-5a42-af94-0c598a691e15', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', '7ebdda22-51a3-5d5a-89ad-bdb805661263', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 93, false),
      ('7d15ed2c-d450-5a9f-8fa5-711fc4ba6c68', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', '7ebdda22-51a3-5d5a-89ad-bdb805661263', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 93, false),
      ('84197416-ef5c-5f1b-b77b-14081156ffa5', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', '7ebdda22-51a3-5d5a-89ad-bdb805661263', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 93, false),
      ('4b423082-7a65-5678-a0d3-0fb7d9ed2e2e', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'e073a6db-61f8-5805-ba9d-8edfe3e980f4', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 93, false),
      ('ed10281e-2a54-54e5-aa0b-dc94e2163c9e', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'e073a6db-61f8-5805-ba9d-8edfe3e980f4', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 93, false),
      ('e5bd3e12-8617-5e60-b3ac-99ab1f6df1b6', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'e073a6db-61f8-5805-ba9d-8edfe3e980f4', null, 3, 5, null, 'colheres (sopa)', null, 'Leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 93, false),
      ('ae00da6d-b9c8-5b57-96bf-e89ec6d53052', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'e073a6db-61f8-5805-ba9d-8edfe3e980f4', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 93, false),
      ('a8e98989-d499-5bd7-ad25-951e3e2db994', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'e073a6db-61f8-5805-ba9d-8edfe3e980f4', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 93, false),
      ('4a5b73b4-d2ae-580f-a20d-1f7a22a78dda', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'e073a6db-61f8-5805-ba9d-8edfe3e980f4', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 93, false),
      ('5332377b-83d5-5640-8e3d-bbab26a0c538', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'e073a6db-61f8-5805-ba9d-8edfe3e980f4', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 93, false),
      ('4382e8f7-f867-599f-9a2c-9ed6c70d5517', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'e073a6db-61f8-5805-ba9d-8edfe3e980f4', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 93, false),
      ('d1538445-3cb6-5ff8-b96f-edcd5c4a30e7', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'e073a6db-61f8-5805-ba9d-8edfe3e980f4', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 93, false),
      ('a33ad654-8b53-5993-bebe-057bf0f8e62c', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'e073a6db-61f8-5805-ba9d-8edfe3e980f4', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 93, false),
      ('6f4ee578-fb78-5f3f-bc96-5ddd48c5a0a7', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'e073a6db-61f8-5805-ba9d-8edfe3e980f4', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 93, false),
      ('4dd2268f-71a9-5b3f-98dc-dfe4098ba419', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'e073a6db-61f8-5805-ba9d-8edfe3e980f4', 'b9c850ce-e18b-58e0-aaa8-9dad5110b902', 12, 350, null, 'g', null, 'chocolate em gotas ou chocolate em barra picado', null, null, 'linear', false, '350g de chocolate em gotas ou chocolate em barra picado', 93, false),
      ('abf786d3-b302-5741-9558-872b28d5f5de', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'f8b52580-ebcb-5a79-8be8-bfceaacbccbc', '71151d78-31dd-5a06-b9b4-e75b87b5a54b', 1, 200, null, 'g', null, 'chocolate meio amargo fracionado ou tipo cobertura', null, null, 'linear', false, '200g de chocolate meio amargo fracionado ou tipo cobertura', 95, false),
      ('d438ef8e-d2ca-56b2-b718-323be1cc0f53', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'f8b52580-ebcb-5a79-8be8-bfceaacbccbc', null, 2, 1, null, 'unidade', null, 'placa de textura', null, null, 'linear', false, 'Uma placa de textura de 10cm de altura', 95, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('bc43fbc9-d3cb-54d2-a3b0-268e73b2c53d', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', '7ebdda22-51a3-5d5a-89ad-bdb805661263', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 94, false),
      ('6362ce63-1cc9-58ec-8cc0-b8f530dbe1c9', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', '7ebdda22-51a3-5d5a-89ad-bdb805661263', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 94, false),
      ('5cb3c561-8606-5f33-9ce2-8b9c2d2c107e', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'e073a6db-61f8-5805-ba9d-8edfe3e980f4', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 94, false),
      ('f9b2c49a-c493-5269-8f85-88386ed2274c', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'e073a6db-61f8-5805-ba9d-8edfe3e980f4', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 94, false),
      ('f082cac6-e8af-5368-9932-ad4304671b69', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'e073a6db-61f8-5805-ba9d-8edfe3e980f4', 3, 'Acrescente a margarina e sove até atingir o ponto de véu, esticando uma pequena porção até ficar transparente sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 94, false),
      ('0cad0a37-870f-5991-b11a-7ae040205812', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'e073a6db-61f8-5805-ba9d-8edfe3e980f4', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente. A massa é macia e pegajosa, e suas mãos precisam do óleo para mexer.', null, 94, false),
      ('2518e3e7-8bff-5328-b20d-c4f4faaf427f', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'e073a6db-61f8-5805-ba9d-8edfe3e980f4', 5, 'Abra a massa em superfície untada com óleo e espalhe as gotas de chocolate; enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as gotas de chocolate. Enrole bem e modele formando uma bola', null, 94, false),
      ('5b1f5241-e7f7-5c7f-b284-8fa5bd6c895e', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'e073a6db-61f8-5805-ba9d-8edfe3e980f4', 6, 'Coloque em uma tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 95, false),
      ('4bf9add8-247b-5f63-80c8-d371707bbf72', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'e073a6db-61f8-5805-ba9d-8edfe3e980f4', 7, 'Volte para a superfície untada, divida em duas partes do mesmo tamanho e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 95, false),
      ('f273c754-722c-5567-815f-19b4bdc6f105', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'e073a6db-61f8-5805-ba9d-8edfe3e980f4', 8, 'Aguarde a massa crescer até a borda e asse em forno preaquecido a 180 graus por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 95, false),
      ('a92bb74d-2dc3-519c-aa8d-5f52a1a28446', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'e073a6db-61f8-5805-ba9d-8edfe3e980f4', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 95, false),
      ('f9eba957-c206-572d-83d3-674fa6dc88ef', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'f8b52580-ebcb-5a79-8be8-bfceaacbccbc', 1, 'Derreta o chocolate no micro-ondas de 30 em 30 segundos ou em banho-maria.', 'Derreta o chocolate no micro-ondas de 30 em 30 segundos ou em banho-maria.', null, 95, false),
      ('7ed5db58-40e0-5e8f-8d42-cd711ca95ce7', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'f8b52580-ebcb-5a79-8be8-bfceaacbccbc', 2, 'Espalhe o chocolate sobre a placa de textura com a profundidade virada para cima, cobrindo toda a placa sem camada muito grossa; retire os excessos.', 'Espalhe o chocolate sobre a placa de textura com a profundidade virada para cima, cobrindo toda a placa sem camada muito grossa; retire os excessos.', null, 96, false),
      ('cc511ca5-9d72-5154-b1ef-c53f3eccc414', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'f8b52580-ebcb-5a79-8be8-bfceaacbccbc', 3, 'Aguarde até tocar a placa e o dedo não sair sujo de chocolate; pode escorrer um pouco ao envolver o chocotone.', 'Aguarde até tocar a placa e o dedo não sair sujo de chocolate; pode escorrer um pouco ao envolver o chocotone.', null, 96, false),
      ('0fedce69-0391-561d-9cce-1dd900d3ca40', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'f8b52580-ebcb-5a79-8be8-bfceaacbccbc', 4, 'Envolva toda a lateral do chocotone com a placa e fixe com fita adesiva.', 'Envolva toda a lateral do chocotone com a placa e fixe com fita adesiva.', null, 96, false),
      ('ebf98bf2-141b-5e7a-9c1b-83ca87172402', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'f8b52580-ebcb-5a79-8be8-bfceaacbccbc', 5, 'Leve à geladeira por 5 minutos ou até endurecer completamente.', 'Leve à geladeira por 5 minutos ou até endurecer completamente.', null, 96, false),
      ('fd48ad7c-3e89-5212-9a21-c9735d99871b', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'f8b52580-ebcb-5a79-8be8-bfceaacbccbc', 6, 'Retire a fita e puxe a placa delicadamente.', 'Retire a fita e puxe a placa delicadamente.', null, 96, false),
      ('5302d146-f500-598a-aaa1-8dc52b586657', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', '89c7fb6f-6c35-5879-9a5d-55666f897ef3', 1, 'Corte o topo do Chocotone e reserve.', 'Comece cortando o topo do Chocotone e reserve.', null, 95, false),
      ('41493ae1-ab73-5e36-b290-dc768c9e3c67', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', '89c7fb6f-6c35-5879-9a5d-55666f897ef3', 2, 'Abra uma cavidade com faca e colher, deixando um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Chocotone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Chocotone não perder a estrutura e quebrar).', null, 96, false),
      ('34a01e72-83a4-53ac-a262-cb68b92adb1a', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', '89c7fb6f-6c35-5879-9a5d-55666f897ef3', 3, 'Adicione o recheio com uma colher ou saco de confeitar.', 'Depois adicione o recheio com uma colher ou um saco de confeitar. A receita sugere rechear com brigadeiro ou recheio de preferência e decorar a parte superior.', null, 96, false),
      ('3161b5ce-e572-5ba3-af38-eb60918afd46', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', '89c7fb6f-6c35-5879-9a5d-55666f897ef3', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa, quando indicado na receita.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 96, false),
      ('95cc9e2c-798f-57a7-8119-d9714ac0c139', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', '89c7fb6f-6c35-5879-9a5d-55666f897ef3', 5, 'Recoloque a tampa e finalize conforme a decoração indicada na receita.', 'Por último coloque a tampa do seu Panetone/Chocotone e decore da maneira de sua preferência, usando sua criatividade.', null, 96, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('156b716f-4f1f-530e-96f1-8b72f2180a0d', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'natal'),
      ('10fd37e5-a140-524c-bc09-77196277ff74', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'chocotone')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('54016794-c47b-50c7-964c-1fcc4acc3792', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', null, 'recipe', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'yield', 'warning', 'A apostila informa rendimento de 5 unidades de 500g, mas também orienta dividir a massa em duas partes. Confirmar o rendimento na revisão.', 94),
      ('cacdbcb1-63c3-5e0a-bd51-f6d63e106903', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', null, 'recipe', '3ca180c0-e1e0-5205-b6f3-62d946e670fa', 'source_pages', 'warning', 'Paginação baseada na transcrição enviada; conferir no PDF original antes da publicação.', 93)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Chocotone Ferrero Rocher
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = 'bc22d3a4-d37b-5496-8975-1a7ee0adc383')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = 'bc22d3a4-d37b-5496-8975-1a7ee0adc383')
     and not exists (select 1 from public.recipe_steps where recipe_id = 'bc22d3a4-d37b-5496-8975-1a7ee0adc383') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('46c98c63-ae1e-5f42-9d70-b1c93f448acb', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', null, 'esponja', 'Esponja', null, null, 1, 1, 34, 35),
      ('4b78d27c-f163-576e-ba93-31f219cc5f2f', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', null, 'massa', 'Massa do Chocotone', null, null, 1, 2, 34, 35),
      ('3bbb6d54-2189-5ac5-8b04-6256e5991cb2', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', null, 'recheio', 'Recheio de Ferrero Rocher', null, null, 1, 3, 36, 37),
      ('7f7cbe1e-6b27-52f3-b090-2ebd44369546', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', null, 'montagem', 'Montagem — Chocotone Ferrero Rocher', null, null, 1, 4, 36, 37)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('c5961902-4cdb-5583-aa07-82287e6d1ba2', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '46c98c63-ae1e-5f42-9d70-b1c93f448acb', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 34, false),
      ('6c734729-8f7e-51d1-ac19-f1161a222f26', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '46c98c63-ae1e-5f42-9d70-b1c93f448acb', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 34, false),
      ('294b61a4-fb6d-5a6f-8192-4c47513dd144', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '46c98c63-ae1e-5f42-9d70-b1c93f448acb', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 34, false),
      ('d85acd72-6786-5c7c-9c47-665637b42456', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '4b78d27c-f163-576e-ba93-31f219cc5f2f', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 34, false),
      ('4dcfe8cc-826c-52c1-9f42-1bd9f415cca2', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '4b78d27c-f163-576e-ba93-31f219cc5f2f', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 34, false),
      ('02d43b47-9d0f-5ff1-a6cd-f7aec4bd5f29', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '4b78d27c-f163-576e-ba93-31f219cc5f2f', null, 3, 5, null, 'colheres (sopa)', null, 'Leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 34, false),
      ('1cc7c6e6-eb39-5b15-af29-59cf50549467', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '4b78d27c-f163-576e-ba93-31f219cc5f2f', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 34, false),
      ('9f371c0b-7baa-51c3-8303-44dd99e0dc85', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '4b78d27c-f163-576e-ba93-31f219cc5f2f', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 34, false),
      ('92b35589-2c43-5e7e-9660-29a8313b3533', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '4b78d27c-f163-576e-ba93-31f219cc5f2f', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 34, false),
      ('3cf98aaf-ff58-5bc7-8998-55cb134383f2', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '4b78d27c-f163-576e-ba93-31f219cc5f2f', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 34, false),
      ('9deed939-e7c4-55a8-a15f-d360b2ed5b3c', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '4b78d27c-f163-576e-ba93-31f219cc5f2f', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 34, false),
      ('fa148fad-e737-5578-afd5-049a5f490590', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '4b78d27c-f163-576e-ba93-31f219cc5f2f', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 34, false),
      ('858d2e70-bf20-5c64-b706-d9ecc3a9ab17', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '4b78d27c-f163-576e-ba93-31f219cc5f2f', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 34, false),
      ('c2c70cee-606e-5d58-8847-ded5d6b6024d', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '4b78d27c-f163-576e-ba93-31f219cc5f2f', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 34, false),
      ('a7d476b0-75a7-55a0-8bc4-5369739916aa', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '4b78d27c-f163-576e-ba93-31f219cc5f2f', 'b9c850ce-e18b-58e0-aaa8-9dad5110b902', 12, 350, null, 'g', null, 'chocolate em gotas ou chocolate em barra picado', null, null, 'linear', false, '350g de chocolate em gotas ou chocolate em barra picado', 34, false),
      ('030e57e8-a810-5cf8-a7a2-3ebcc4c1602e', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '3bbb6d54-2189-5ac5-8b04-6256e5991cb2', '562bc70c-661f-5b07-8a95-eb8378d53841', 1, 180, null, 'g', null, 'Nutella', null, null, 'linear', false, '180g Nutella (1 pote pequeno)', 36, false),
      ('d042a76a-f522-56ae-bac1-12b504558f19', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '3bbb6d54-2189-5ac5-8b04-6256e5991cb2', '8758d73e-4fcf-508e-940d-635708436a41', 2, 100, null, 'g', null, 'creme de leite', null, null, 'linear', false, '100g creme de leite', 36, false),
      ('4cd5afd1-80a5-5892-90a5-400b36c66ac6', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '3bbb6d54-2189-5ac5-8b04-6256e5991cb2', null, 3, 50, null, 'g', null, 'castanha de caju picada', null, null, 'linear', false, '50g Castanha de Caju picada a gosto', 36, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('546d150f-5e83-5c10-8159-b8f31e35a70c', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '46c98c63-ae1e-5f42-9d70-b1c93f448acb', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 35, false),
      ('7787e73d-ff14-5427-a4ad-b03f4b9920ca', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '46c98c63-ae1e-5f42-9d70-b1c93f448acb', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 35, false),
      ('6ddd6f8a-a933-506b-9f2b-c8f62489af1b', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '4b78d27c-f163-576e-ba93-31f219cc5f2f', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 35, false),
      ('f9583774-a9ad-58e7-b2dc-139bee62201b', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '4b78d27c-f163-576e-ba93-31f219cc5f2f', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 35, false),
      ('d7956dae-0dc6-5c64-b4dc-beebf57c6af9', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '4b78d27c-f163-576e-ba93-31f219cc5f2f', 3, 'Acrescente a margarina e sove até atingir o ponto de véu, esticando uma pequena porção até ficar transparente sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 35, false),
      ('31f6baf8-3e9a-58c3-ae51-06cc8a02c743', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '4b78d27c-f163-576e-ba93-31f219cc5f2f', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente. A massa é macia e pegajosa, e suas mãos precisam do óleo para mexer.', null, 35, false),
      ('eb6d8c91-6b04-577c-8259-a6e898bf78c5', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '4b78d27c-f163-576e-ba93-31f219cc5f2f', 5, 'Abra a massa em superfície untada com óleo e espalhe as gotas de chocolate; enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as gotas de chocolate. Enrole bem e modele formando uma bola', null, 35, false),
      ('cfaf3af1-7fcf-57d2-8eb0-4bb49e918cd4', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '4b78d27c-f163-576e-ba93-31f219cc5f2f', 6, 'Coloque em uma tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 36, false),
      ('a2300b88-2dc8-5420-9eb4-41284d85d1fa', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '4b78d27c-f163-576e-ba93-31f219cc5f2f', 7, 'Volte para a superfície untada, divida em duas partes do mesmo tamanho e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 36, false),
      ('cb9ae5ac-2cd7-58c8-9c5d-1b1d5f10d210', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '4b78d27c-f163-576e-ba93-31f219cc5f2f', 8, 'Aguarde a massa crescer até a borda e asse em forno preaquecido a 180 graus por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 36, false),
      ('ceb62259-e87f-57b8-a108-6ffe051cd8ab', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '4b78d27c-f163-576e-ba93-31f219cc5f2f', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 36, false),
      ('db111ac0-51b5-5e22-b857-a1991faf550d', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '3bbb6d54-2189-5ac5-8b04-6256e5991cb2', 1, 'Misture todos os ingredientes. Não precisa levar ao fogo.', 'Misture todos os ingredientes. Não precisa levar ao fogo.', null, 36, false),
      ('8f574880-734a-5831-914b-789bfdc7d62c', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '7f7cbe1e-6b27-52f3-b090-2ebd44369546', 1, 'Corte o topo do Chocotone e reserve.', 'Comece cortando o topo do Chocotone e reserve.', null, 36, false),
      ('a853d775-76a8-57c2-9b02-6b7bf61fff25', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '7f7cbe1e-6b27-52f3-b090-2ebd44369546', 2, 'Abra uma cavidade com faca e colher, deixando um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Chocotone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Chocotone não perder a estrutura e quebrar).', null, 37, false),
      ('2b271eeb-7103-5b00-9dd7-0c722c9f2065', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '7f7cbe1e-6b27-52f3-b090-2ebd44369546', 3, 'Adicione o recheio com uma colher ou saco de confeitar.', 'Depois adicione o recheio com uma colher ou um saco de confeitar. Decore com um pouco do recheio e, se desejar, bombons Ferrero Rocher.', null, 37, false),
      ('6d94878a-63eb-5d10-a131-45515a44ea14', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '7f7cbe1e-6b27-52f3-b090-2ebd44369546', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa, quando indicado na receita.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 37, false),
      ('89fb7313-016a-57c7-91a2-b1b488f9334f', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', '7f7cbe1e-6b27-52f3-b090-2ebd44369546', 5, 'Recoloque a tampa e finalize conforme a decoração indicada na receita.', 'Por último coloque a tampa do seu Panetone/Chocotone e decore da maneira de sua preferência, usando sua criatividade.', null, 37, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('02e02abe-bfe0-57d2-9650-9727f2692d15', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', 'natal'),
      ('ae0c2bbb-55b0-5f6b-9e88-32bc2bce9935', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', 'chocotone')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('9fd4c580-cc5e-594a-9fc7-f564d916b2b6', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', null, 'recipe', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', 'yield', 'warning', 'A apostila informa rendimento de 5 unidades de 500g, mas também orienta dividir a massa em duas partes. Confirmar o rendimento na revisão.', 35),
      ('9cf9d026-3bc4-5cc7-86e0-1c7bd0049d3a', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', null, 'recipe', 'bc22d3a4-d37b-5496-8975-1a7ee0adc383', 'source_pages', 'warning', 'Paginação baseada na transcrição enviada; conferir no PDF original antes da publicação.', 34)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Chocotone Infantil
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e')
     and not exists (select 1 from public.recipe_steps where recipe_id = '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('f6a1656b-e3f9-5d71-a93e-542e5f667e51', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', null, 'esponja', 'Esponja', null, null, 1, 1, 109, 110),
      ('fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', null, 'massa', 'Massa do Chocotone', null, null, 1, 2, 109, 110),
      ('e83b8f1d-6180-5a95-9a4b-8eda2f03499d', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', null, 'recheio', 'Recheio de Brigadeiro', null, null, 1, 3, 111, 112),
      ('af2ca419-01a4-5009-bec4-2d511ab5b576', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', null, 'montagem', 'Montagem — Chocotone Infantil', null, null, 1, 4, 111, 112)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('d2e1e79d-c1a7-5c9e-94ba-83590df321f8', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'f6a1656b-e3f9-5d71-a93e-542e5f667e51', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 109, false),
      ('382a996b-4895-52ac-801c-5720b06831bf', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'f6a1656b-e3f9-5d71-a93e-542e5f667e51', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 109, false),
      ('3695514c-ba96-5d74-8929-40c9e902022d', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'f6a1656b-e3f9-5d71-a93e-542e5f667e51', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 109, false),
      ('6ae9c015-7bbf-5459-b753-7cab6bb5c9e7', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 109, false),
      ('45ff4e22-64ef-514a-98dd-593fa19b199f', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 109, false),
      ('d8ce7a5f-ee3a-5d31-aa3b-c4628ec5e9cd', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', null, 3, 5, null, 'colheres (sopa)', null, 'Leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 109, false),
      ('775677b4-b421-50ac-8901-18efc0443b57', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 109, false),
      ('de79c3db-ca72-5f39-a9ec-2568b97ccaa7', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 109, false),
      ('860671c1-bb21-56bb-bd31-742bd4918a72', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 109, false),
      ('c15cd223-d8d3-55de-a74b-4489187c9269', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 109, false),
      ('c93f64f9-57e8-5aef-a322-c6f6c9dd0f59', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 109, false),
      ('43a49d21-e5e5-5f71-82d5-c7f913e8be1f', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 109, false),
      ('2f8f5e09-8f6c-5b58-80e7-87dbe78bc41a', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 109, false),
      ('9dda1802-ad4a-524b-859b-629dc444a637', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 109, false),
      ('7c627b40-9e8e-5061-a1e9-7f1d91ba71da', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', 'b9c850ce-e18b-58e0-aaa8-9dad5110b902', 12, 350, null, 'g', null, 'chocolate em gotas ou chocolate em barra picado', null, null, 'linear', false, '350g de chocolate em gotas ou chocolate em barra picado', 109, false),
      ('3a3006fc-7f41-501b-8f94-12ef875ca725', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'e83b8f1d-6180-5a95-9a4b-8eda2f03499d', '6b34b876-9b3f-5612-96da-1abcf6f11bbc', 1, 1, null, 'unidade', null, 'leite condensado', null, null, 'linear', false, '1 leite condensado', 111, false),
      ('715d8e0f-8c70-59b8-b267-c5b140d5629a', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'e83b8f1d-6180-5a95-9a4b-8eda2f03499d', null, 2, 1, null, 'colher (café)', null, 'manteiga', null, null, 'linear', false, '1 colher (café) manteiga', 111, false),
      ('1df5c3e5-7e91-57fb-a577-802847491d12', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'e83b8f1d-6180-5a95-9a4b-8eda2f03499d', '8758d73e-4fcf-508e-940d-635708436a41', 3, 1, null, 'unidade', null, 'creme de leite', null, null, 'linear', false, '1 creme de leite', 111, false),
      ('2994ef9b-ea84-5e88-9d87-ef7d7fd1abef', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'e83b8f1d-6180-5a95-9a4b-8eda2f03499d', null, 4, 50, null, 'g', null, 'cacau 50%', null, null, 'linear', false, '50g de cacau 50%', 111, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('986967bc-2667-588c-b93a-f53272208536', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'f6a1656b-e3f9-5d71-a93e-542e5f667e51', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 110, false),
      ('ed1f13cd-282c-57a6-a3bd-6cf77273fdfd', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'f6a1656b-e3f9-5d71-a93e-542e5f667e51', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 110, false),
      ('bc01b8c0-03db-5dcf-86e5-ce2be65b0e4f', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 110, false),
      ('d5eda22b-6f76-53a4-be8f-b0463d2bbf79', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 110, false),
      ('096dbe6c-1ab2-5b89-a1b1-ed953a6a5b22', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', 3, 'Acrescente a margarina e sove até atingir o ponto de véu, esticando uma pequena porção até ficar transparente sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 110, false),
      ('49488e48-0063-583b-bbdb-04018813fd45', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente. A massa é macia e pegajosa, e suas mãos precisam do óleo para mexer.', null, 110, false),
      ('1c3a921b-4078-5af3-bccb-a4cd7f3381d2', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', 5, 'Abra a massa em superfície untada com óleo e espalhe as gotas de chocolate; enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as gotas de chocolate. Enrole bem e modele formando uma bola', null, 110, false),
      ('a210e9b3-9df9-5d96-8d45-e4a36892e308', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', 6, 'Coloque em uma tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 111, false),
      ('e9919511-71a3-5d89-8d02-d1d8fba78fc8', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', 7, 'Volte para a superfície untada, divida em duas partes do mesmo tamanho e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 111, false),
      ('ce7ac092-0fa0-52fa-80d0-fc8f60c21872', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', 8, 'Aguarde a massa crescer até a borda e asse em forno preaquecido a 180 graus por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 111, false),
      ('df3d7860-1541-5e63-b00c-f308e1d3c241', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'fd6e519b-e2b6-5b4c-9e97-fe14f7a650ad', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 111, false),
      ('77427302-168b-5b28-b5e9-e19dba2cd2ab', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'e83b8f1d-6180-5a95-9a4b-8eda2f03499d', 1, 'Leve todos os ingredientes ao fogo em panela de fundo grosso.', 'Leve todos os ingredientes ao fogo em panela de fundo grosso.', null, 111, false),
      ('7e83a2f5-78d8-549d-8e53-5af7d1730659', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'e83b8f1d-6180-5a95-9a4b-8eda2f03499d', 2, 'Mexa até engrossar e começar a desgrudar do fundo da panela. Deixe esfriar em temperatura ambiente.', 'Mexa até engrossar e começar a desgrudar do fundo da panela. Deixe esfriar em temperatura ambiente.', null, 112, false),
      ('db2ac7c4-f5aa-50cb-87bc-8e8cfac9a5b2', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'af2ca419-01a4-5009-bec4-2d511ab5b576', 1, 'Corte o topo do Chocotone e reserve.', 'Comece cortando o topo do Chocotone e reserve.', null, 111, false),
      ('a441592b-bf56-50c4-a74a-6ef60fa5dc3e', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'af2ca419-01a4-5009-bec4-2d511ab5b576', 2, 'Abra uma cavidade com faca e colher, deixando um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Chocotone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Chocotone não perder a estrutura e quebrar).', null, 112, false),
      ('b0f9986c-d1d5-5370-88a4-ce300723494f', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'af2ca419-01a4-5009-bec4-2d511ab5b576', 3, 'Adicione o recheio com uma colher ou saco de confeitar.', 'Depois adicione o recheio com uma colher ou um saco de confeitar. Coloque um pouco de M&M’s junto ao recheio. Decore com M&M’s, pirulitos e Kinder Ovo, conforme a preferência.', null, 112, false),
      ('176c7e7e-f2e7-51fe-9332-9f175b97aca6', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'af2ca419-01a4-5009-bec4-2d511ab5b576', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa, quando indicado na receita.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 112, false),
      ('353fb8ad-c2a6-5e90-aaee-b52eea648c8c', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'af2ca419-01a4-5009-bec4-2d511ab5b576', 5, 'Recoloque a tampa e finalize conforme a decoração indicada na receita.', 'Por último coloque a tampa do seu Panetone/Chocotone e decore da maneira de sua preferência, usando sua criatividade.', null, 112, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('45b1981e-bb78-5208-a112-694df98c162f', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'natal'),
      ('e47024a1-c5c4-5918-9d39-4e8288e0279a', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'chocotone')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('ebdf02c6-6ebe-5348-94bb-5ecff1431687', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', null, 'recipe', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'yield', 'warning', 'A apostila informa rendimento de 5 unidades de 500g, mas também orienta dividir a massa em duas partes. Confirmar o rendimento na revisão.', 110),
      ('16925d12-e16d-5d24-a53f-66821661febc', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', null, 'recipe', '9abfcd1c-b065-5bb6-8de9-33b6e0fc1d0e', 'source_pages', 'warning', 'Paginação baseada na transcrição enviada; conferir no PDF original antes da publicação.', 109)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Chocotone Kinder Bueno
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = 'dc77b330-46fd-5257-afaa-235c8c5915f4')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = 'dc77b330-46fd-5257-afaa-235c8c5915f4')
     and not exists (select 1 from public.recipe_steps where recipe_id = 'dc77b330-46fd-5257-afaa-235c8c5915f4') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('9b63778d-97b7-5e7e-a8ab-417a17e9a159', 'dc77b330-46fd-5257-afaa-235c8c5915f4', null, 'esponja', 'Esponja', null, null, 1, 1, 101, 102),
      ('583fac7c-62e3-566f-8734-7fb1ed313c0d', 'dc77b330-46fd-5257-afaa-235c8c5915f4', null, 'massa', 'Massa do Chocotone', null, null, 1, 2, 101, 102),
      ('7997b5c0-d96f-5f3f-84cc-a028dd975814', 'dc77b330-46fd-5257-afaa-235c8c5915f4', null, 'recheio', 'Recheio Kinder Bueno', null, null, 1, 3, 103, 104),
      ('e7a9af51-15c1-5990-936a-14d23cc6dbcb', 'dc77b330-46fd-5257-afaa-235c8c5915f4', null, 'montagem', 'Montagem — Chocotone Kinder Bueno', null, null, 1, 4, 103, 104)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('6ff92bb2-571a-5f31-bdf5-1cb7be05ce55', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '9b63778d-97b7-5e7e-a8ab-417a17e9a159', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 101, false),
      ('842c254c-b1f6-5b2f-b5d1-f8cb242556d6', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '9b63778d-97b7-5e7e-a8ab-417a17e9a159', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 101, false),
      ('1d2adf7b-128f-525e-ae53-5cb3f9e3895f', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '9b63778d-97b7-5e7e-a8ab-417a17e9a159', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 101, false),
      ('e9070bfb-28f3-59de-8fd6-6d2d51c8390a', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '583fac7c-62e3-566f-8734-7fb1ed313c0d', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 101, false),
      ('a841c60f-8883-54d2-bc6b-72120b42cf8c', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '583fac7c-62e3-566f-8734-7fb1ed313c0d', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 101, false),
      ('e604f948-946d-592b-8ca4-de29cb9c7813', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '583fac7c-62e3-566f-8734-7fb1ed313c0d', null, 3, 5, null, 'colheres (sopa)', null, 'Leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 101, false),
      ('c53c7cf6-52cb-5175-9150-6aa25ba8689a', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '583fac7c-62e3-566f-8734-7fb1ed313c0d', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 101, false),
      ('cdc5cf1b-05ba-5b4d-a737-cbdba27b248c', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '583fac7c-62e3-566f-8734-7fb1ed313c0d', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 101, false),
      ('7a4e191e-ee62-5a14-8135-65dcb9fe5167', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '583fac7c-62e3-566f-8734-7fb1ed313c0d', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 101, false),
      ('5c75539d-c4ae-5ccc-98b7-58e75ff4414b', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '583fac7c-62e3-566f-8734-7fb1ed313c0d', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 101, false),
      ('41fda1a3-56c3-58b7-94ab-b03a5fb5a711', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '583fac7c-62e3-566f-8734-7fb1ed313c0d', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 101, false),
      ('bd850428-e24f-5d21-a351-c769cc12ffe2', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '583fac7c-62e3-566f-8734-7fb1ed313c0d', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 101, false),
      ('41e4e407-e32e-504f-9adf-87ad78f64079', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '583fac7c-62e3-566f-8734-7fb1ed313c0d', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 101, false),
      ('3a9a5951-a4b8-5bba-bba5-1fca00a7605c', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '583fac7c-62e3-566f-8734-7fb1ed313c0d', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 101, false),
      ('f2d4b544-e370-59e4-9ad4-a446ceb43cff', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '583fac7c-62e3-566f-8734-7fb1ed313c0d', 'b9c850ce-e18b-58e0-aaa8-9dad5110b902', 12, 350, null, 'g', null, 'chocolate em gotas ou chocolate em barra picado', null, null, 'linear', false, '350g de chocolate em gotas ou chocolate em barra picado', 101, false),
      ('346d4f78-475b-5ce6-afb3-d295f6c96455', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '7997b5c0-d96f-5f3f-84cc-a028dd975814', '6b34b876-9b3f-5612-96da-1abcf6f11bbc', 1, 1, null, 'unidade', null, 'leite condensado', null, null, 'linear', false, '1 leite condensado', 103, false),
      ('58536d52-4a55-5eb1-a297-c19a6aff235c', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '7997b5c0-d96f-5f3f-84cc-a028dd975814', '8758d73e-4fcf-508e-940d-635708436a41', 2, 2, null, 'unidades', null, 'creme de leite', null, null, 'linear', false, '2 creme de leite', 103, false),
      ('ba519b35-32e6-5403-902e-1d62acef36a8', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '7997b5c0-d96f-5f3f-84cc-a028dd975814', '40245c07-39b0-5a2c-b610-edc6bb3fb56b', 3, 100, null, 'g', null, 'chocolate branco', null, null, 'linear', false, '100g de chocolate branco', 103, false),
      ('d8daa980-c91f-5622-a752-511e826c806f', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '7997b5c0-d96f-5f3f-84cc-a028dd975814', null, 4, 3, null, 'unidades', null, 'Kinder Bueno', null, null, 'linear', false, '3 kinder bueno', 103, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('eb368ac3-d194-5d87-afbb-ea164e1eba6c', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '9b63778d-97b7-5e7e-a8ab-417a17e9a159', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 102, false),
      ('358ed218-9450-552c-b06a-7962a6c9a500', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '9b63778d-97b7-5e7e-a8ab-417a17e9a159', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 102, false),
      ('30133338-5599-5eea-914f-87fe502479df', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '583fac7c-62e3-566f-8734-7fb1ed313c0d', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 102, false),
      ('b3bdba3b-f7f9-5a97-b7fb-6bb1cebf39ec', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '583fac7c-62e3-566f-8734-7fb1ed313c0d', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 102, false),
      ('20573955-c1e3-5dd7-98df-282d0b247d6c', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '583fac7c-62e3-566f-8734-7fb1ed313c0d', 3, 'Acrescente a margarina e sove até atingir o ponto de véu, esticando uma pequena porção até ficar transparente sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 102, false),
      ('537ff9d5-2a3c-5f24-a74a-b47b2091c366', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '583fac7c-62e3-566f-8734-7fb1ed313c0d', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente. A massa é macia e pegajosa, e suas mãos precisam do óleo para mexer.', null, 102, false),
      ('d6e8ade8-57cc-543e-94c8-f244b99c53ad', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '583fac7c-62e3-566f-8734-7fb1ed313c0d', 5, 'Abra a massa em superfície untada com óleo e espalhe as gotas de chocolate; enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as gotas de chocolate. Enrole bem e modele formando uma bola', null, 102, false),
      ('788bc722-f644-571d-a3a3-236749aac3d6', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '583fac7c-62e3-566f-8734-7fb1ed313c0d', 6, 'Coloque em uma tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 103, false),
      ('b9740f06-5264-555b-9969-846300b05c5a', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '583fac7c-62e3-566f-8734-7fb1ed313c0d', 7, 'Volte para a superfície untada, divida em duas partes do mesmo tamanho e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 103, false),
      ('62bb9157-a568-5820-85c8-75a0687be90f', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '583fac7c-62e3-566f-8734-7fb1ed313c0d', 8, 'Aguarde a massa crescer até a borda e asse em forno preaquecido a 180 graus por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 103, false),
      ('be5ba5b4-4559-5131-a35d-346a63a4ce7c', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '583fac7c-62e3-566f-8734-7fb1ed313c0d', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 103, false),
      ('b512135e-0b1b-5bbe-adac-b702fdb1157b', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '7997b5c0-d96f-5f3f-84cc-a028dd975814', 1, 'Leve ao fogo médio todos os ingredientes, exceto os Kinder Bueno, e mexa até o ponto de brigadeiro mole.', 'Leve ao fogo médio todos os ingredientes, exceto os Kinder Bueno, e mexa até o ponto de brigadeiro mole.', null, 103, false),
      ('363e4daa-7030-5ee0-8f61-d0dfe365f2da', 'dc77b330-46fd-5257-afaa-235c8c5915f4', '7997b5c0-d96f-5f3f-84cc-a028dd975814', 2, 'Desligue e deixe esfriar por completo.', 'Desligue e deixe esfriar por completo.', null, 104, false),
      ('752c971b-17ce-5497-ae88-98e342d9ea60', 'dc77b330-46fd-5257-afaa-235c8c5915f4', 'e7a9af51-15c1-5990-936a-14d23cc6dbcb', 1, 'Corte o topo do Chocotone e reserve.', 'Comece cortando o topo do Chocotone e reserve.', null, 103, false),
      ('a3118071-754a-5700-9fc9-736f3a8b1894', 'dc77b330-46fd-5257-afaa-235c8c5915f4', 'e7a9af51-15c1-5990-936a-14d23cc6dbcb', 2, 'Abra uma cavidade com faca e colher, deixando um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Chocotone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Chocotone não perder a estrutura e quebrar).', null, 104, false),
      ('a064353b-a24a-52f5-a70c-f9000ed60dff', 'dc77b330-46fd-5257-afaa-235c8c5915f4', 'e7a9af51-15c1-5990-936a-14d23cc6dbcb', 3, 'Adicione o recheio com uma colher ou saco de confeitar.', 'Depois adicione o recheio com uma colher ou um saco de confeitar. Adicione um pouco de Kinder Bueno picado junto ao recheio e finalize com recheio e pedaços do chocolate.', null, 104, false),
      ('90c26ea7-4c50-5194-939c-548fbda89080', 'dc77b330-46fd-5257-afaa-235c8c5915f4', 'e7a9af51-15c1-5990-936a-14d23cc6dbcb', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa, quando indicado na receita.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 104, false),
      ('6c8ab351-7722-5460-a9e0-1629d0188a54', 'dc77b330-46fd-5257-afaa-235c8c5915f4', 'e7a9af51-15c1-5990-936a-14d23cc6dbcb', 5, 'Recoloque a tampa e finalize conforme a decoração indicada na receita.', 'Por último coloque a tampa do seu Panetone/Chocotone e decore da maneira de sua preferência, usando sua criatividade.', null, 104, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('d6e17d54-ee10-5a5f-bc45-273510e0647d', 'dc77b330-46fd-5257-afaa-235c8c5915f4', 'natal'),
      ('097cc1dd-a0fd-5d7c-8b9a-6d00432013f6', 'dc77b330-46fd-5257-afaa-235c8c5915f4', 'chocotone')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('4883b03e-8e3b-5130-97de-9139d803895f', 'dc77b330-46fd-5257-afaa-235c8c5915f4', null, 'recipe', 'dc77b330-46fd-5257-afaa-235c8c5915f4', 'yield', 'warning', 'A apostila informa rendimento de 5 unidades de 500g, mas também orienta dividir a massa em duas partes. Confirmar o rendimento na revisão.', 102),
      ('21b10113-d7ab-5f8d-ba33-b7eff8d77d4f', 'dc77b330-46fd-5257-afaa-235c8c5915f4', null, 'recipe', 'dc77b330-46fd-5257-afaa-235c8c5915f4', 'source_pages', 'warning', 'Paginação baseada na transcrição enviada; conferir no PDF original antes da publicação.', 101)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Chocotone Laka
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = '155006a3-77a9-5248-bca7-a7624fc3795d')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = '155006a3-77a9-5248-bca7-a7624fc3795d')
     and not exists (select 1 from public.recipe_steps where recipe_id = '155006a3-77a9-5248-bca7-a7624fc3795d') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('fdbae3b2-cf44-532b-8e25-340ca6e6d55e', '155006a3-77a9-5248-bca7-a7624fc3795d', null, 'esponja', 'Esponja', null, null, 1, 1, 85, 86),
      ('c660512d-12d2-5eb9-9aaf-91826ca215fb', '155006a3-77a9-5248-bca7-a7624fc3795d', null, 'massa', 'Massa do Chocotone', null, null, 1, 2, 85, 86),
      ('6f39f22d-6eef-56cd-81bb-05398e5c9cc5', '155006a3-77a9-5248-bca7-a7624fc3795d', null, 'recheio', 'Recheio de Laka', null, null, 1, 3, 87, 88),
      ('0be07488-2788-59a6-b4c3-ec2d3843425a', '155006a3-77a9-5248-bca7-a7624fc3795d', null, 'montagem', 'Montagem — Chocotone Laka', null, null, 1, 4, 87, 88)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('b6d0b2c8-ecc3-5171-9583-066469742e2d', '155006a3-77a9-5248-bca7-a7624fc3795d', 'fdbae3b2-cf44-532b-8e25-340ca6e6d55e', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 85, false),
      ('b44ae5fa-b842-56df-a21d-56edc40836c3', '155006a3-77a9-5248-bca7-a7624fc3795d', 'fdbae3b2-cf44-532b-8e25-340ca6e6d55e', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 85, false),
      ('4e548aa5-3e29-5f5c-90bd-b76613841d88', '155006a3-77a9-5248-bca7-a7624fc3795d', 'fdbae3b2-cf44-532b-8e25-340ca6e6d55e', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 85, false),
      ('94344a44-de2a-51c7-bda6-62d7163bb223', '155006a3-77a9-5248-bca7-a7624fc3795d', 'c660512d-12d2-5eb9-9aaf-91826ca215fb', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 85, false),
      ('ebfcd870-200c-5c3c-ba82-125debb6f169', '155006a3-77a9-5248-bca7-a7624fc3795d', 'c660512d-12d2-5eb9-9aaf-91826ca215fb', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 85, false),
      ('98181045-d35e-5379-a075-44e83e862925', '155006a3-77a9-5248-bca7-a7624fc3795d', 'c660512d-12d2-5eb9-9aaf-91826ca215fb', null, 3, 5, null, 'colheres (sopa)', null, 'Leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 85, false),
      ('460df57e-2c4f-54c1-9dd3-af11eab2ce31', '155006a3-77a9-5248-bca7-a7624fc3795d', 'c660512d-12d2-5eb9-9aaf-91826ca215fb', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 85, false),
      ('9e680097-ed08-5e66-a1ea-99a75cb8b97d', '155006a3-77a9-5248-bca7-a7624fc3795d', 'c660512d-12d2-5eb9-9aaf-91826ca215fb', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 85, false),
      ('3cefc25e-ef51-53ef-8ca4-20f26c614295', '155006a3-77a9-5248-bca7-a7624fc3795d', 'c660512d-12d2-5eb9-9aaf-91826ca215fb', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 85, false),
      ('b9587530-a018-5967-b592-38197c503725', '155006a3-77a9-5248-bca7-a7624fc3795d', 'c660512d-12d2-5eb9-9aaf-91826ca215fb', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 85, false),
      ('2c4034f4-0637-51c4-b0dc-0321a695f7a1', '155006a3-77a9-5248-bca7-a7624fc3795d', 'c660512d-12d2-5eb9-9aaf-91826ca215fb', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 85, false),
      ('081d9c46-9b8f-5027-b30e-a4383c002876', '155006a3-77a9-5248-bca7-a7624fc3795d', 'c660512d-12d2-5eb9-9aaf-91826ca215fb', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 85, false),
      ('2e5de776-3c0d-5a44-9c4a-7a85b472fcf6', '155006a3-77a9-5248-bca7-a7624fc3795d', 'c660512d-12d2-5eb9-9aaf-91826ca215fb', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 85, false),
      ('2d034456-73ae-5f53-92b6-eb32eada66de', '155006a3-77a9-5248-bca7-a7624fc3795d', 'c660512d-12d2-5eb9-9aaf-91826ca215fb', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 85, false),
      ('7062551d-9414-5718-b7fa-f190b472873f', '155006a3-77a9-5248-bca7-a7624fc3795d', 'c660512d-12d2-5eb9-9aaf-91826ca215fb', 'b9c850ce-e18b-58e0-aaa8-9dad5110b902', 12, 350, null, 'g', null, 'chocolate em gotas ou chocolate em barra picado', null, null, 'linear', false, '350g de chocolate em gotas ou chocolate em barra picado', 85, false),
      ('b427d9a9-ce54-5892-a482-89e3e5054994', '155006a3-77a9-5248-bca7-a7624fc3795d', '6f39f22d-6eef-56cd-81bb-05398e5c9cc5', '6b34b876-9b3f-5612-96da-1abcf6f11bbc', 1, 1, null, 'unidade', null, 'leite condensado', null, null, 'linear', false, '1 leite condensado', 87, false),
      ('070d40d3-b754-56d7-80c2-ac3d0355f871', '155006a3-77a9-5248-bca7-a7624fc3795d', '6f39f22d-6eef-56cd-81bb-05398e5c9cc5', '8758d73e-4fcf-508e-940d-635708436a41', 2, 1, null, 'unidade', null, 'creme de leite', null, null, 'linear', false, '1 creme de leite', 87, false),
      ('7cdb525b-8476-528e-bba1-a9293898de8c', '155006a3-77a9-5248-bca7-a7624fc3795d', '6f39f22d-6eef-56cd-81bb-05398e5c9cc5', null, 3, 100, null, 'g', null, 'chocolate Laka picado', null, null, 'linear', false, '100g de chocolate Laka picado', 87, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('d38aa6a8-9684-5102-bc53-7238df6b5976', '155006a3-77a9-5248-bca7-a7624fc3795d', 'fdbae3b2-cf44-532b-8e25-340ca6e6d55e', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 86, false),
      ('a3731196-2ba3-5ab6-b95e-45b44e20cdc0', '155006a3-77a9-5248-bca7-a7624fc3795d', 'fdbae3b2-cf44-532b-8e25-340ca6e6d55e', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 86, false),
      ('3e69d9ae-81dc-5dac-a29d-f3925c3dc799', '155006a3-77a9-5248-bca7-a7624fc3795d', 'c660512d-12d2-5eb9-9aaf-91826ca215fb', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 86, false),
      ('3d0ebf21-aae3-51ed-bcca-08f496a63873', '155006a3-77a9-5248-bca7-a7624fc3795d', 'c660512d-12d2-5eb9-9aaf-91826ca215fb', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 86, false),
      ('a8a3ad7b-7c86-5f5d-9121-533acf8e662b', '155006a3-77a9-5248-bca7-a7624fc3795d', 'c660512d-12d2-5eb9-9aaf-91826ca215fb', 3, 'Acrescente a margarina e sove até atingir o ponto de véu, esticando uma pequena porção até ficar transparente sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 86, false),
      ('e88de925-6849-52b0-bdce-d9db9cc1b795', '155006a3-77a9-5248-bca7-a7624fc3795d', 'c660512d-12d2-5eb9-9aaf-91826ca215fb', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente. A massa é macia e pegajosa, e suas mãos precisam do óleo para mexer.', null, 86, false),
      ('00cecaa4-37be-5337-a8ee-5c8f58082c0b', '155006a3-77a9-5248-bca7-a7624fc3795d', 'c660512d-12d2-5eb9-9aaf-91826ca215fb', 5, 'Abra a massa em superfície untada com óleo e espalhe as gotas de chocolate; enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as gotas de chocolate. Enrole bem e modele formando uma bola', null, 86, false),
      ('3d02d866-58a1-58c4-83b2-322340e82952', '155006a3-77a9-5248-bca7-a7624fc3795d', 'c660512d-12d2-5eb9-9aaf-91826ca215fb', 6, 'Coloque em uma tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 87, false),
      ('1729cb5c-e1ff-57f4-8c22-920f3ed91549', '155006a3-77a9-5248-bca7-a7624fc3795d', 'c660512d-12d2-5eb9-9aaf-91826ca215fb', 7, 'Volte para a superfície untada, divida em duas partes do mesmo tamanho e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 87, false),
      ('76c8c75d-f733-5ee5-97a2-055efaf330da', '155006a3-77a9-5248-bca7-a7624fc3795d', 'c660512d-12d2-5eb9-9aaf-91826ca215fb', 8, 'Aguarde a massa crescer até a borda e asse em forno preaquecido a 180 graus por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 87, false),
      ('e0b8eee7-c9c2-5783-bc49-4065c86c91ba', '155006a3-77a9-5248-bca7-a7624fc3795d', 'c660512d-12d2-5eb9-9aaf-91826ca215fb', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 87, false),
      ('ede00e77-f1eb-5074-9543-0a610953197c', '155006a3-77a9-5248-bca7-a7624fc3795d', '6f39f22d-6eef-56cd-81bb-05398e5c9cc5', 1, 'Misture o leite condensado e o creme de leite em panela de fundo grosso.', 'Misture o leite condensado e o creme de leite em panela de fundo grosso.', null, 87, false),
      ('a8092b18-80c0-50b0-8f5c-d1c461522908', '155006a3-77a9-5248-bca7-a7624fc3795d', '6f39f22d-6eef-56cd-81bb-05398e5c9cc5', 2, 'Leve ao fogo e mexa por 5 minutos; adicione o chocolate Laka picado e continue mexendo até engrossar e aparecer o fundo da panela. Deixe esfriar.', 'Leve ao fogo e mexa por 5 minutos; adicione o chocolate Laka picado e continue mexendo até engrossar e aparecer o fundo da panela. Deixe esfriar.', null, 88, false),
      ('5d8aedb1-b2a7-5a56-bb22-5fff7a207c6b', '155006a3-77a9-5248-bca7-a7624fc3795d', '0be07488-2788-59a6-b4c3-ec2d3843425a', 1, 'Corte o topo do Chocotone e reserve.', 'Comece cortando o topo do Chocotone e reserve.', null, 87, false),
      ('f8ac9cf0-d4d5-57cf-be67-19d854ee9cb1', '155006a3-77a9-5248-bca7-a7624fc3795d', '0be07488-2788-59a6-b4c3-ec2d3843425a', 2, 'Abra uma cavidade com faca e colher, deixando um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Chocotone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Chocotone não perder a estrutura e quebrar).', null, 88, false),
      ('809002f7-be25-5bec-b596-c83f6d091c57', '155006a3-77a9-5248-bca7-a7624fc3795d', '0be07488-2788-59a6-b4c3-ec2d3843425a', 3, 'Adicione o recheio com uma colher ou saco de confeitar.', 'Depois adicione o recheio com uma colher ou um saco de confeitar. Finalize com pedaços de chocolate Laka.', null, 88, false),
      ('508abb63-b9e1-5cc5-9e74-cc51b32de047', '155006a3-77a9-5248-bca7-a7624fc3795d', '0be07488-2788-59a6-b4c3-ec2d3843425a', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa, quando indicado na receita.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 88, false),
      ('8b4d973c-f923-5513-a5f7-496591ab7089', '155006a3-77a9-5248-bca7-a7624fc3795d', '0be07488-2788-59a6-b4c3-ec2d3843425a', 5, 'Recoloque a tampa e finalize conforme a decoração indicada na receita.', 'Por último coloque a tampa do seu Panetone/Chocotone e decore da maneira de sua preferência, usando sua criatividade.', null, 88, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('24edc117-dcef-58b5-834a-b3f354493629', '155006a3-77a9-5248-bca7-a7624fc3795d', 'natal'),
      ('7d1015e8-eaf7-53f5-b954-f4270b532d66', '155006a3-77a9-5248-bca7-a7624fc3795d', 'chocotone')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('69a12dda-458b-59e3-90f0-da7243541326', '155006a3-77a9-5248-bca7-a7624fc3795d', null, 'recipe', '155006a3-77a9-5248-bca7-a7624fc3795d', 'yield', 'warning', 'A apostila informa rendimento de 5 unidades de 500g, mas também orienta dividir a massa em duas partes. Confirmar o rendimento na revisão.', 86),
      ('c5a16c2a-a32b-5b56-b12e-6fd95fec1e9d', '155006a3-77a9-5248-bca7-a7624fc3795d', null, 'recipe', '155006a3-77a9-5248-bca7-a7624fc3795d', 'source_pages', 'warning', 'Paginação baseada na transcrição enviada; conferir no PDF original antes da publicação.', 85)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Chocotone Ovomaltine
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5')
     and not exists (select 1 from public.recipe_steps where recipe_id = 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('931c07e6-378b-5754-86d2-682c0ef887e2', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', null, 'esponja', 'Esponja', null, null, 1, 1, 53, 54),
      ('cf563882-ba44-5b7f-a8c7-2e88621a8d29', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', null, 'massa', 'Massa do Chocotone', null, null, 1, 2, 53, 54),
      ('abb89f04-0901-5417-8980-8f23ee99c647', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', null, 'recheio', 'Recheio de Ovomaltine', null, null, 1, 3, 55, 56),
      ('bb3a54eb-667d-58a4-b70f-38778b4a125e', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', null, 'montagem', 'Montagem — Chocotone Ovomaltine', null, null, 1, 4, 55, 56)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('c8e5c979-8b2c-53c2-a1c2-0e3749b466c5', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', '931c07e6-378b-5754-86d2-682c0ef887e2', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 53, false),
      ('c221c8df-980e-5060-9207-8797afa0aef3', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', '931c07e6-378b-5754-86d2-682c0ef887e2', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 53, false),
      ('3d230d9f-bdc4-50a7-afdf-9d0911385b40', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', '931c07e6-378b-5754-86d2-682c0ef887e2', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 53, false),
      ('7c9698c2-cc21-5ce2-8771-a9920fb41e84', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'cf563882-ba44-5b7f-a8c7-2e88621a8d29', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 53, false),
      ('e4d63334-31be-5343-9eba-b1bf6188a620', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'cf563882-ba44-5b7f-a8c7-2e88621a8d29', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 53, false),
      ('b3d78130-72c1-59f7-8a91-c27258a12546', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'cf563882-ba44-5b7f-a8c7-2e88621a8d29', null, 3, 5, null, 'colheres (sopa)', null, 'Leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 53, false),
      ('db1c01df-8fd3-5d04-a000-638904ff8287', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'cf563882-ba44-5b7f-a8c7-2e88621a8d29', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 53, false),
      ('ec4115e0-79db-57a0-a466-6d76b603e854', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'cf563882-ba44-5b7f-a8c7-2e88621a8d29', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 53, false),
      ('10013521-6970-5fef-ae5d-449ced5733ad', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'cf563882-ba44-5b7f-a8c7-2e88621a8d29', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 53, false),
      ('96b93b3f-9821-56c0-a6a0-40aedce37354', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'cf563882-ba44-5b7f-a8c7-2e88621a8d29', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 53, false),
      ('14fd701b-649f-5ce6-a62b-36761717b3d2', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'cf563882-ba44-5b7f-a8c7-2e88621a8d29', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 53, false),
      ('68522bc1-b579-5548-8b62-38cd3fffe8c5', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'cf563882-ba44-5b7f-a8c7-2e88621a8d29', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 53, false),
      ('c667ba1d-1962-5642-9779-b0bafc32fd6a', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'cf563882-ba44-5b7f-a8c7-2e88621a8d29', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 53, false),
      ('f78b4631-8e09-547c-9b8d-2ad1b08c6709', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'cf563882-ba44-5b7f-a8c7-2e88621a8d29', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 53, false),
      ('fc089ced-2a43-59e2-a6eb-76a38fc896b5', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'cf563882-ba44-5b7f-a8c7-2e88621a8d29', '66de60ad-556e-5d31-a00e-33e3d39f9b10', 12, 20, null, 'g', null, 'canela em pó', null, null, 'linear', false, '20g de canela em pó', 53, false),
      ('f71f3621-5932-5dee-8b64-ad622eaa0de3', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'abb89f04-0901-5417-8980-8f23ee99c647', '6b34b876-9b3f-5612-96da-1abcf6f11bbc', 1, 1, null, 'unidade', null, 'leite condensado', null, null, 'linear', false, '1 leite condensado', 55, false),
      ('946ff3c0-53c4-5d7a-b320-7f55f41c8b93', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'abb89f04-0901-5417-8980-8f23ee99c647', '8758d73e-4fcf-508e-940d-635708436a41', 2, 1, null, 'unidade', null, 'creme de leite', null, null, 'linear', false, '1 creme de leite', 55, false),
      ('9cff12d7-8d80-5e6c-b1e8-f76a1d7b2fe9', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'abb89f04-0901-5417-8980-8f23ee99c647', 'b4d783c2-7628-5681-8a23-e61a1d392617', 3, 200, null, 'g', null, 'Ovomaltine em pó', null, null, 'linear', false, '200g de Ovomaltine em pó', 55, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('61e3b4fb-96cf-5f88-955c-032bb132f8fb', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', '931c07e6-378b-5754-86d2-682c0ef887e2', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 54, false),
      ('ec3ebc83-e256-501f-83b0-75bdfdfad070', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', '931c07e6-378b-5754-86d2-682c0ef887e2', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 54, false),
      ('e74f176c-82a2-5835-8274-2253a7763b64', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'cf563882-ba44-5b7f-a8c7-2e88621a8d29', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 54, false),
      ('da23eb9a-4982-552a-8510-6b25739d8ce9', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'cf563882-ba44-5b7f-a8c7-2e88621a8d29', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, a canela em pó, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 54, false),
      ('6b8d7778-56c9-5a6b-959b-d05a9767e6d9', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'cf563882-ba44-5b7f-a8c7-2e88621a8d29', 3, 'Acrescente a margarina e sove até atingir o ponto de véu, esticando uma pequena porção até ficar transparente sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 54, false),
      ('f9d970fa-b0e3-5002-9354-879f0cca4044', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'cf563882-ba44-5b7f-a8c7-2e88621a8d29', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente. A massa é macia e pegajosa, e suas mãos precisam do óleo para mexer.', null, 54, false),
      ('5b7109b3-c059-580c-833a-1c93f570e4a7', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'cf563882-ba44-5b7f-a8c7-2e88621a8d29', 5, 'Abra a massa em superfície untada com óleo e espalhe as gotas de chocolate; enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as gotas de chocolate. Enrole bem e modele formando uma bola', null, 54, false),
      ('5a8bc775-0b33-54d4-bb6e-09c97951594b', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'cf563882-ba44-5b7f-a8c7-2e88621a8d29', 6, 'Coloque em uma tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 55, false),
      ('715e0de2-cc68-5b1b-9345-3b2eb38e6e85', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'cf563882-ba44-5b7f-a8c7-2e88621a8d29', 7, 'Volte para a superfície untada, divida em duas partes do mesmo tamanho e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 55, false),
      ('2b5e8da5-a328-5921-a163-4480c77e805d', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'cf563882-ba44-5b7f-a8c7-2e88621a8d29', 8, 'Aguarde a massa crescer até a borda e asse em forno preaquecido a 180 graus por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 55, false),
      ('9297cf62-3d95-57e3-931d-4a25949607d0', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'cf563882-ba44-5b7f-a8c7-2e88621a8d29', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 55, false),
      ('1a76e4f3-19d4-5afe-95c2-c31ef2731109', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'abb89f04-0901-5417-8980-8f23ee99c647', 1, 'Leve o leite condensado e o creme de leite ao fogo médio em panela de fundo, mexendo sem parar até o ponto de cobertura (fio reto).', 'Leve o leite condensado e o creme de leite ao fogo médio em panela de fundo, mexendo sem parar até o ponto de cobertura (fio reto).', null, 55, false),
      ('0ec2dda4-9de3-576a-ac71-659ce9a5a486', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'abb89f04-0901-5417-8980-8f23ee99c647', 2, 'Deixe esfriar e misture o Ovomaltine em pó.', 'Deixe esfriar e misture o Ovomaltine em pó.', null, 56, false),
      ('66883659-ade2-5ed0-bfd3-5e85e0ade171', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'bb3a54eb-667d-58a4-b70f-38778b4a125e', 1, 'Corte o topo do Chocotone e reserve.', 'Comece cortando o topo do Chocotone e reserve.', null, 55, false),
      ('3f7ef71d-04e2-5cf9-9bea-c928607ce864', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'bb3a54eb-667d-58a4-b70f-38778b4a125e', 2, 'Abra uma cavidade com faca e colher, deixando um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Chocotone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Chocotone não perder a estrutura e quebrar).', null, 56, false),
      ('8b0773dc-233a-57e2-8904-cf18aedb9085', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'bb3a54eb-667d-58a4-b70f-38778b4a125e', 3, 'Adicione o recheio com uma colher ou saco de confeitar.', 'Depois adicione o recheio com uma colher ou um saco de confeitar. Decore com uma fita vermelha ou a gosto.', null, 56, false),
      ('e509a99b-482b-5937-98cc-8ea81603bcac', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'bb3a54eb-667d-58a4-b70f-38778b4a125e', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa, quando indicado na receita.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 56, false),
      ('26882ffd-033d-5991-9985-15a94e57a909', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'bb3a54eb-667d-58a4-b70f-38778b4a125e', 5, 'Recoloque a tampa e finalize conforme a decoração indicada na receita.', 'Por último coloque a tampa do seu Panetone/Chocotone e decore da maneira de sua preferência, usando sua criatividade.', null, 56, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('88f4ce5d-d7fd-5635-8b80-96eda03c86d4', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'natal'),
      ('f7070bf2-4007-5ec9-9714-fbac083014c0', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'chocotone')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('4a7c6082-02ac-5dd1-9aa1-4df129808177', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', null, 'recipe', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'yield', 'warning', 'A apostila informa rendimento de 5 unidades de 500g, mas também orienta dividir a massa em duas partes. Confirmar o rendimento na revisão.', 54),
      ('905ff03c-61cd-5299-9358-2d3e2d38c7a2', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', null, 'recipe', 'ba561fc7-16e0-5dd4-8fe3-a007d775bfc5', 'source_pages', 'warning', 'Paginação baseada na transcrição enviada; conferir no PDF original antes da publicação.', 53)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Chocotone Tradicional
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31')
     and not exists (select 1 from public.recipe_steps where recipe_id = 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('57e84f67-1db2-5d20-9ee2-88bcc1e342ca', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', null, 'esponja', 'Esponja', null, null, 1, 1, 22, 23),
      ('ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', null, 'massa', 'Massa do Chocotone', null, null, 1, 2, 22, 24)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('79e7fcf4-c4b5-55e2-90fc-06783e715750', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', '57e84f67-1db2-5d20-9ee2-88bcc1e342ca', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 22, false),
      ('7ee2b69d-c8f6-5b5a-91fd-fa5eba89441e', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', '57e84f67-1db2-5d20-9ee2-88bcc1e342ca', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 22, false),
      ('aa57c219-1b2a-5df3-8cfb-af84bf36c6c3', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', '57e84f67-1db2-5d20-9ee2-88bcc1e342ca', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 22, false),
      ('2de7f99a-dfd8-57c9-a690-77bd590b3db9', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 22, false),
      ('5b69030f-c944-588b-9a1b-cfc54c31e2fd', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 22, false),
      ('9360ef0c-f36a-56a4-a909-5ca04acd83f2', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', '9b1e65ad-f9ce-50fa-aa1c-9d934b76e83c', 3, 5, null, 'colheres (sopa)', null, 'leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 22, false),
      ('53fab360-5198-59dd-9fa7-d51c234b88b9', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 22, false),
      ('ca1bce9d-338a-5b1b-99db-3ae3d3036246', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 22, false),
      ('e6a00fe6-2797-5116-a2e9-6bd77df205a2', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 22, false),
      ('ce2b1b86-52a7-54d3-8008-a7116d4e2001', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 22, false),
      ('be0eec1c-1ed1-518a-a17c-817578cc03c2', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 22, false),
      ('51b64085-f312-5045-a8a4-92555a3aae7a', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 22, false),
      ('117e3b0a-9168-5f45-812c-106f68130b21', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 22, false),
      ('f04e09ff-a653-5d7e-8923-8729f00fb5bd', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 22, false),
      ('11289a39-6261-52c8-b6bf-b69ae95ffcef', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', null, 12, 350, null, 'g', null, 'chocolate em gotas ou chocolate em barra picado', null, null, 'linear', false, '350g de chocolate em gotas ou chocolate em barra picado', 22, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('54ae765e-caf5-5ecc-8a9c-f1ff220d617c', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', '57e84f67-1db2-5d20-9ee2-88bcc1e342ca', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 23, false),
      ('9ff11d09-d844-5384-8abb-60bd05f1cfc5', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', '57e84f67-1db2-5d20-9ee2-88bcc1e342ca', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 23, false),
      ('74e9692c-3386-5d0c-8c56-3c3bf9280ab4', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 23, false),
      ('a3a16dc5-309d-5532-9586-9a2fcd969b8e', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 23, false),
      ('fc17f198-8ccc-56e5-96f6-17e3da820134', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', 3, 'Acrescente a margarina e sove até atingir o ponto de véu, abrindo a massa até ficar transparente sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 23, false),
      ('9f21270f-1b8f-5ace-9415-f538859cb31c', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente.', null, 23, false),
      ('253f2661-e4a0-503d-9fdc-be4e68324740', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', 5, 'Abra a massa em superfície untada com óleo, espalhe as gotas de chocolate, enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as gotas de chocolate. Enrole bem e modele formando uma bola', null, 23, false),
      ('8fef4c4f-e657-5bde-948a-273383935a45', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', 6, 'Coloque em tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 24, false),
      ('87746d71-e663-53eb-be63-19a10a438295', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', 7, 'Volte a massa para a superfície untada, divida em duas partes iguais e coloque nas formas de papel; a massa deve ficar até a metade da forma.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 24, false),
      ('82213349-ab3b-5304-b927-35e47e01b13b', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', 8, 'Aguarde crescer até a borda e asse em forno preaquecido a 180°C por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 24, false),
      ('666d4091-33bf-5727-b970-9a0301ec533c', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'ce2ada8a-c336-5c9c-87a3-84ff71d9acdd', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 24, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('2812013b-7fa2-5577-ada9-144e6d97fb70', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'natal'),
      ('5b480417-a27f-5b61-afad-542166d2fd47', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'chocotone'),
      ('c9fb1eae-6d40-5b65-8efc-e619d05eb902', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'chocolate')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('f7700be6-1e5e-565f-a526-98237c847ba1', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', null, 'recipe', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'yield', 'warning', 'O texto informa rendimento de 5 Chocotones de 500g, mas também orienta dividir a massa em duas partes. Confirmar esse rendimento na revisão.', 24),
      ('8319e446-2b42-5a66-ba91-579c143201fb', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', null, 'recipe', 'bbd729e3-e82b-5258-9fb5-8e5fd4e75d31', 'source_pages', 'warning', 'As páginas são as apresentadas na transcrição enviada nesta conversa; conferir a paginação no PDF original antes da publicação.', 22)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Chocotone Trufado
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82')
     and not exists (select 1 from public.recipe_steps where recipe_id = 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('2b26fdce-ae19-5df7-9f4a-fe864936eacf', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', null, 'esponja', 'Esponja', null, null, 1, 1, 49, 50),
      ('58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', null, 'massa', 'Massa do Chocotone', null, null, 1, 2, 49, 50),
      ('9e56cf86-e80e-5a6b-8af8-e61ea0e9b448', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', null, 'recheio', 'Trufa Tradicional', null, null, 1, 3, 51, 52),
      ('b4fa6418-d93d-5825-ad9d-ae4d0d7f1d68', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', null, 'montagem', 'Montagem — Chocotone Trufado', null, null, 1, 4, 51, 52)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('86132c4b-9fc5-599b-bbdf-294cfeeca31e', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '2b26fdce-ae19-5df7-9f4a-fe864936eacf', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 49, false),
      ('c91ff24b-5c98-59a8-a18d-232d578bbc91', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '2b26fdce-ae19-5df7-9f4a-fe864936eacf', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 49, false),
      ('d8ec29aa-4e3a-5c5f-a6d8-0426f56bc44f', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '2b26fdce-ae19-5df7-9f4a-fe864936eacf', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 49, false),
      ('c74b6398-acf3-548c-b195-12de5ce8c912', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 49, false),
      ('90add251-33e6-5e4b-97c4-a9d29a57ba05', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 49, false),
      ('f75c293d-2170-5603-8131-dbb404c4f8fd', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', null, 3, 5, null, 'colheres (sopa)', null, 'Leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 49, false),
      ('2dfdd267-d166-5da9-a0e5-f822beca8334', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 49, false),
      ('9c14e2a7-1e0a-515c-bc51-8c3e81e5dd19', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 49, false),
      ('682e5bc6-7a17-50af-81cb-0beb89e2e762', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 49, false),
      ('bf17c262-cc1b-57b6-bba6-8e7f9d9d6c42', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 49, false),
      ('3c07c5b0-d263-5922-ba39-63451d5a1895', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 49, false),
      ('59648b41-1199-5823-ab51-31ad1db2dd90', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 49, false),
      ('aa2a2dd8-6803-5f90-bb53-1ec92c21f15e', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 49, false),
      ('a9de0099-6774-55a9-981a-784fed7a4a0f', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 49, false),
      ('e678ac45-7525-501b-967c-c998d2cadd61', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', 'b9c850ce-e18b-58e0-aaa8-9dad5110b902', 12, 350, null, 'g', null, 'chocolate em gotas ou chocolate em barra picado', null, null, 'linear', false, '350g de chocolate em gotas ou chocolate em barra picado', 49, false),
      ('aa95a375-85cb-5c72-90ec-4fa82278dc0a', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '9e56cf86-e80e-5a6b-8af8-e61ea0e9b448', 'cf8c47db-5462-5c96-906c-bd05adf51ea3', 1, 400, null, 'g', null, 'chocolate nobre meio amargo', null, null, 'linear', false, '400g de chocolate nobre meio amargo', 51, false),
      ('05aa1c28-4ab1-587e-abcc-8c0c34dec7c6', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '9e56cf86-e80e-5a6b-8af8-e61ea0e9b448', '8758d73e-4fcf-508e-940d-635708436a41', 2, 200, null, 'ml', null, 'creme de leite', null, null, 'linear', false, '1 creme de leite (200ml)', 51, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('c244d11c-972c-5bbc-9869-752d0dfa2953', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '2b26fdce-ae19-5df7-9f4a-fe864936eacf', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 50, false),
      ('5e359b49-b8de-5153-b864-e0ec2d6bcbd2', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '2b26fdce-ae19-5df7-9f4a-fe864936eacf', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 50, false),
      ('bd05810d-bfc4-58e1-a48c-8d636936e46d', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 50, false),
      ('662ead48-25dc-59be-b997-e69c3f06ed6f', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 50, false),
      ('66315bc9-9b6d-581a-97cf-e83e94bd25a1', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', 3, 'Acrescente a margarina e sove até atingir o ponto de véu, esticando uma pequena porção até ficar transparente sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 50, false),
      ('f67330ad-d0f0-591e-8ef3-882cd60853d5', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente. A massa é macia e pegajosa, e suas mãos precisam do óleo para mexer.', null, 50, false),
      ('58397614-0a1d-5495-8cec-eac9a25b22f5', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', 5, 'Abra a massa em superfície untada com óleo e espalhe as gotas de chocolate; enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as gotas de chocolate. Enrole bem e modele formando uma bola', null, 50, false),
      ('db1edf11-729f-5e35-9071-0aa3bb0efdee', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', 6, 'Coloque em uma tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 51, false),
      ('4a405ffd-8f31-544d-8b5f-27f234317ca2', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', 7, 'Volte para a superfície untada, divida em duas partes do mesmo tamanho e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 51, false),
      ('402f5e1b-b7f4-5f30-96cd-4d170929d7dc', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', 8, 'Aguarde a massa crescer até a borda e asse em forno preaquecido a 180 graus por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 51, false),
      ('f0db6633-f39a-5d4b-a102-63d1e6ac0420', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '58c0feb8-3bdf-5ef4-8323-b29bb3b607fd', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 51, false),
      ('8a61d0ab-8f95-5411-bcae-6e928ed809af', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '9e56cf86-e80e-5a6b-8af8-e61ea0e9b448', 1, 'Derreta o chocolate no micro-ondas de 30 em 30 segundos ou em banho-maria.', 'Derreta o chocolate no micro-ondas de 30 em 30 segundos ou em banho-maria.', null, 51, false),
      ('aeb5301c-168d-5caf-a951-cbe2cb7e9457', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '9e56cf86-e80e-5a6b-8af8-e61ea0e9b448', 2, 'Misture o creme de leite até ficar homogêneo.', 'Misture o creme de leite até ficar homogêneo.', null, 52, false),
      ('f68f07ca-2fb6-59ae-9301-5ec1ace1376f', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', '9e56cf86-e80e-5a6b-8af8-e61ea0e9b448', 3, 'Deixe esfriar completamente antes de rechear.', 'Deixe esfriar completamente antes de rechear.', null, 52, false),
      ('10f2610d-4aa2-57aa-99e7-adacf6804f23', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', 'b4fa6418-d93d-5825-ad9d-ae4d0d7f1d68', 1, 'Corte o topo do Chocotone e reserve.', 'Comece cortando o topo do Chocotone e reserve.', null, 51, false),
      ('82011a14-fd43-5f55-80dc-bd968b4e660b', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', 'b4fa6418-d93d-5825-ad9d-ae4d0d7f1d68', 2, 'Abra uma cavidade com faca e colher, deixando um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Chocotone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Chocotone não perder a estrutura e quebrar).', null, 52, false),
      ('55db3d1e-27b5-5a49-8a33-20a6c473438a', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', 'b4fa6418-d93d-5825-ad9d-ae4d0d7f1d68', 3, 'Adicione o recheio com uma colher ou saco de confeitar.', 'Depois adicione o recheio com uma colher ou um saco de confeitar. A cobertura é feita com 200g de chocolate fracionado ou tipo cobertura derretido; despeje sobre o topo e deixe escorrer nas laterais. A transcrição da montagem cita recheio de Maracujá, embora esta ficha apresente trufa tradicional; conferir esse trecho na revisão.', null, 52, false),
      ('e868ca07-b860-5271-8877-a0902aee334e', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', 'b4fa6418-d93d-5825-ad9d-ae4d0d7f1d68', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa, quando indicado na receita.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 52, false),
      ('c92c1006-cfb7-5006-b20c-43f4a8beec23', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', 'b4fa6418-d93d-5825-ad9d-ae4d0d7f1d68', 5, 'Recoloque a tampa e finalize conforme a decoração indicada na receita.', 'Por último coloque a tampa do seu Panetone/Chocotone e decore da maneira de sua preferência, usando sua criatividade.', null, 52, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('12ed47f0-571c-5384-bc10-5679a3137495', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', 'natal'),
      ('8a50fe59-beb0-55a0-a23c-af92921ba460', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', 'chocotone')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('f42cbaa9-c4e7-5dc8-b32b-9da2a7f4c44b', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', null, 'recipe', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', 'yield', 'warning', 'A apostila informa rendimento de 5 unidades de 500g, mas também orienta dividir a massa em duas partes. Confirmar o rendimento na revisão.', 50),
      ('d7ea3151-9cd0-5939-bd7a-452a8b0a7b35', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', null, 'recipe', 'd2af5983-6d59-57ab-b58b-0aabfa5e6c82', 'source_pages', 'warning', 'Paginação baseada na transcrição enviada; conferir no PDF original antes da publicação.', 49)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Panetone/Chocotone no Pote
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = '47d81496-9268-5d71-9e83-4475e751a3af')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = '47d81496-9268-5d71-9e83-4475e751a3af')
     and not exists (select 1 from public.recipe_steps where recipe_id = '47d81496-9268-5d71-9e83-4475e751a3af') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('60d18f12-a201-5832-8575-51ff8412bdac', '47d81496-9268-5d71-9e83-4475e751a3af', null, 'calda', 'Calda de Panetone', null, null, 1, 1, 114, 114),
      ('f074e3c1-4105-53c6-9c9d-735a9bf2cc64', '47d81496-9268-5d71-9e83-4475e751a3af', null, 'montagem', 'Montagem do Panetone/Chocotone no Pote', null, null, 1, 2, 114, 115)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('366883f3-bdb4-564a-8ba6-d1425b92402c', '47d81496-9268-5d71-9e83-4475e751a3af', '60d18f12-a201-5832-8575-51ff8412bdac', 'f5c19bc6-2479-5ec4-9abe-d4aceecc1f8e', 1, 500, null, 'ml', null, 'água', null, null, 'linear', false, '500ml de água', 114, false),
      ('22c71f02-0087-568c-b1c0-43d26070b3fe', '47d81496-9268-5d71-9e83-4475e751a3af', '60d18f12-a201-5832-8575-51ff8412bdac', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 2, null, 'colheres (café)', null, 'açúcar', null, null, 'linear', false, '2 colheres (café) de açúcar', 114, false),
      ('c8ab3008-ac64-5c5f-bc51-5a62a054a451', '47d81496-9268-5d71-9e83-4475e751a3af', '60d18f12-a201-5832-8575-51ff8412bdac', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 3, 10, null, 'gotas', null, 'essência de Panetone', null, null, 'linear', false, '10 gotas de essência de Panetone', 114, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('c3e5dcb5-e969-5954-8cf4-1d02c1946760', '47d81496-9268-5d71-9e83-4475e751a3af', '60d18f12-a201-5832-8575-51ff8412bdac', 1, 'Misture todos os ingredientes e deixe ferver por 5 minutos. Deixe esfriar.', 'Basta misturar todos os ingredientes e deixar ferver por 5 minutos. Depois é só deixar esfriar.', null, 114, false),
      ('4a2278c6-40e1-5354-9b10-9c17a2e92378', '47d81496-9268-5d71-9e83-4475e751a3af', 'f074e3c1-4105-53c6-9c9d-735a9bf2cc64', 1, 'Use potes de 250ml.', 'Recomendo usar Potes de 250ml.', null, 115, false),
      ('e2a1492e-1b4a-5399-b7e1-28d2d71e5540', '47d81496-9268-5d71-9e83-4475e751a3af', 'f074e3c1-4105-53c6-9c9d-735a9bf2cc64', 2, 'Esfarele o miolo retirado do Panetone ou Chocotone; também é possível preparar uma receita e esfarelar.', 'Comece esfarelando o miolo retirado do Panetone ou Chocotone.', null, 115, false),
      ('ae1e0b76-0fec-587b-956c-99dfc6c5d592', '47d81496-9268-5d71-9e83-4475e751a3af', 'f074e3c1-4105-53c6-9c9d-735a9bf2cc64', 3, 'Preencha o fundo com uma camada de miolo e umedeça com a calda.', 'Preencha o fundo do pote com uma camada de Panetone ou Chocotone e umedeça com a calda.', null, 115, false),
      ('f716eb68-234a-546e-9fc0-bca3e4fc011c', '47d81496-9268-5d71-9e83-4475e751a3af', 'f074e3c1-4105-53c6-9c9d-735a9bf2cc64', 4, 'Adicione uma camada do recheio de sua preferência e intercale miolo, calda e recheio até completar o pote.', 'Em seguida coloque uma camada do recheio de sua preferência, e vá intercalando Panetone, calda e recheio até completar o pote.', null, 115, false),
      ('6cdfd5c8-f285-5fb3-84e8-d33ef0ebfd94', '47d81496-9268-5d71-9e83-4475e751a3af', 'f074e3c1-4105-53c6-9c9d-735a9bf2cc64', 5, 'Finalize com frutas ou raspas de chocolate; pode colocar uma fita vermelha na parte exterior.', 'Finalize com frutas na parte superior ou raspas de chocolate. Pode colocar também uma fita vermelha na parte exterior.', null, 115, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('1948338f-b5f6-5ae3-b2f5-8ccfb77e613a', '47d81496-9268-5d71-9e83-4475e751a3af', 'natal'),
      ('61fbeb26-3aab-5827-9daf-ce415a9b928f', '47d81496-9268-5d71-9e83-4475e751a3af', 'panetone'),
      ('8d424393-6972-5eee-857c-7df7aebf8b4b', '47d81496-9268-5d71-9e83-4475e751a3af', 'chocotone'),
      ('cdce0927-e9bb-5022-88fb-98aab1abeed9', '47d81496-9268-5d71-9e83-4475e751a3af', 'sobremesa-no-pote')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('6bbecc3a-c163-531b-bf3e-c5fe6d3ef067', '47d81496-9268-5d71-9e83-4475e751a3af', null, 'recipe', '47d81496-9268-5d71-9e83-4475e751a3af', 'yield', 'warning', 'O rendimento informado é médio: cada receita de recheio rende cerca de 3 potes. Confirmar na revisão.', 114)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Panetone com Cobertura Natalina
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668')
     and not exists (select 1 from public.recipe_steps where recipe_id = '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('e3c35df8-63e4-54b8-b3ef-fc13d44a61e9', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', null, 'esponja', 'Esponja', null, null, 1, 1, 89, 90),
      ('67b1174a-70ce-5b4e-8713-b2931b423408', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', null, 'massa', 'Massa do Panetone', null, null, 1, 2, 89, 90),
      ('5a0af2d1-9493-53db-8bfd-d60cd4915777', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', null, 'recheio', 'Cobertura Natalina', null, null, 1, 3, 91, 92),
      ('a3fd9f78-24a5-5452-86fb-696f2d5cb8a6', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', null, 'montagem', 'Montagem — Panetone com Cobertura Natalina', null, null, 1, 4, 91, 92)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('a3791aa6-69d4-5cad-8ddc-b210d58e260a', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', 'e3c35df8-63e4-54b8-b3ef-fc13d44a61e9', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 89, false),
      ('012f0187-51ae-5a9e-9f0c-656719053568', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', 'e3c35df8-63e4-54b8-b3ef-fc13d44a61e9', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 89, false),
      ('8fd100fe-bb66-591e-b8d2-21465bb41b3e', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', 'e3c35df8-63e4-54b8-b3ef-fc13d44a61e9', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 89, false),
      ('7b528ab0-f028-539f-a608-f463121b745f', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 89, false),
      ('fe27434e-a701-5b0a-bafc-f02c0d0bb39f', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 89, false),
      ('15743298-42df-5e5c-a3ab-c441a14052ce', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', null, 3, 5, null, 'colheres (sopa)', null, 'Leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 89, false),
      ('029fcc7f-19a0-5371-aea2-7c8b801e485f', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 89, false),
      ('7157c0e3-7952-50d2-a7fd-747221150528', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 89, false),
      ('578db554-ad06-5184-8de0-301fc283d490', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 89, false),
      ('84cc678e-00ff-593e-87ef-a1200c8e9c6c', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 89, false),
      ('22d5cbe1-55e0-5d49-a717-e209dca5e658', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 89, false),
      ('281484c9-114f-5712-8b52-088759c61a72', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 89, false),
      ('51398aa6-af6a-5663-b635-50f82679ddc9', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 89, false),
      ('937a86cd-c300-5b11-ac44-9ab2742291b6', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 89, false),
      ('67dde716-068e-589c-a5bf-e4e9d36eb4cc', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', '9cf7d3c9-36d9-5e20-9c00-6151636b0ac1', 12, 200, null, 'g', null, 'uvas passas', null, null, 'linear', false, '200g de uvas passas', 89, false),
      ('aae8c205-a89c-5393-aeb5-66971dd7e5aa', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', '523013e5-3b5c-503c-8e3b-0efe15fa5dda', 13, 250, null, 'g', null, 'frutas cristalizadas', null, null, 'linear', false, '250g de frutas cristalizadas', 89, false),
      ('720b73c3-fd0c-52ed-a02d-eb24071253f2', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '5a0af2d1-9493-53db-8bfd-d60cd4915777', null, 1, 500, null, 'g', null, 'açúcar de confeiteiro', null, null, 'linear', false, '500g de açúcar de confeiteiro', 91, false),
      ('68613c12-83d6-572d-af00-b76657032834', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '5a0af2d1-9493-53db-8bfd-d60cd4915777', 'ea4555e0-c258-513c-9d9a-3d81eb730e6a', 2, 100, null, 'ml', null, 'leite', null, null, 'linear', false, '100ml de leite', 91, false),
      ('c24c9542-fa61-5937-be23-9da5b472ac85', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '5a0af2d1-9493-53db-8bfd-d60cd4915777', '9f52288a-886a-53b0-a056-95e9903995b9', 3, 1, null, 'colher (chá)', null, 'manteiga sem sal', null, null, 'linear', false, '1 colher (chá) de manteiga sem sal', 91, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('4388adfb-b0cb-5561-8492-f2829b9679e5', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', 'e3c35df8-63e4-54b8-b3ef-fc13d44a61e9', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 90, false),
      ('ada279cc-7a68-54c8-b103-5d720861853b', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', 'e3c35df8-63e4-54b8-b3ef-fc13d44a61e9', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 90, false),
      ('483b195b-fe9b-55b9-ac2f-929c790dd2f2', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 90, false),
      ('0d9e06e9-5461-5d78-8bde-98221e480c48', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 90, false),
      ('bfd3d7d1-d7a4-5c9c-8f28-f166f14dcf36', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', 3, 'Acrescente a margarina e sove até atingir o ponto de véu, esticando uma pequena porção até ficar transparente sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 90, false),
      ('f8c4f810-b778-5498-903a-15732287412f', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente. A massa é macia e pegajosa, e suas mãos precisam do óleo para mexer.', null, 90, false),
      ('56c45ac2-b1c3-5ade-bd15-6729b5e44aa7', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', 5, 'Abra a massa em superfície untada com óleo e espalhe as uvas passas e frutas cristalizadas; enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as uvas passas e frutas cristalizadas. Enrole bem e modele formando uma bola', null, 90, false),
      ('a28b4cc5-e6bc-5bcb-ba4f-fd5cb8860719', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', 6, 'Coloque em uma tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 91, false),
      ('aa22770f-5499-5412-ae8b-c398f77add23', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', 7, 'Volte para a superfície untada, divida em duas partes do mesmo tamanho e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 91, false),
      ('f32274db-3c90-54d7-8b20-bd523cd58eb7', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', 8, 'Aguarde a massa crescer até a borda e asse em forno preaquecido a 180 graus por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 91, false),
      ('d4b10777-a6c0-5abe-a694-f4c861b1efe1', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '67b1174a-70ce-5b4e-8713-b2931b423408', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 91, false),
      ('00a96a66-2519-5f76-abf4-05960219db81', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '5a0af2d1-9493-53db-8bfd-d60cd4915777', 1, 'Coloque a manteiga e o leite em refratário e leve ao banho-maria.', 'Coloque a manteiga e o leite em refratário e leve ao banho-maria.', null, 91, false),
      ('96a9c26b-a841-5fb8-a099-3f7d3983f22f', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', '5a0af2d1-9493-53db-8bfd-d60cd4915777', 2, 'Acrescente o açúcar de confeiteiro aos poucos, mexendo por 10 minutos ou até ficar líquido. Deixe esfriar por completo.', 'Acrescente o açúcar de confeiteiro aos poucos, mexendo por 10 minutos ou até ficar líquido. Deixe esfriar por completo.', null, 92, false),
      ('619c20a4-a824-573b-a4e7-34226d222158', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', 'a3fd9f78-24a5-5452-86fb-696f2d5cb8a6', 1, 'Corte o topo do Panetone e reserve.', 'Comece cortando o topo do Panetone e reserve.', null, 91, false),
      ('da2ba479-09d4-5aa5-8e5d-a8d36d6d4ef1', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', 'a3fd9f78-24a5-5452-86fb-696f2d5cb8a6', 2, 'Abra uma cavidade com faca e colher, deixando um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Panetone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Panetone não perder a estrutura e quebrar).', null, 92, false),
      ('1ceacda5-0b88-5d45-939e-3b02fdb6394e', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', 'a3fd9f78-24a5-5452-86fb-696f2d5cb8a6', 3, 'Adicione o recheio com uma colher ou saco de confeitar.', 'Depois adicione o recheio com uma colher ou um saco de confeitar. Espalhe a cobertura na parte superior e finalize com frutas cristalizadas.', null, 92, false),
      ('73d61a51-0357-52a1-a761-22126e10c5b7', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', 'a3fd9f78-24a5-5452-86fb-696f2d5cb8a6', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa, quando indicado na receita.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 92, false),
      ('3f4a97dc-7443-5257-a34e-0ce833165ddd', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', 'a3fd9f78-24a5-5452-86fb-696f2d5cb8a6', 5, 'Recoloque a tampa e finalize conforme a decoração indicada na receita.', 'Por último coloque a tampa do seu Panetone/Chocotone e decore da maneira de sua preferência, usando sua criatividade.', null, 92, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('ea2dd6f5-1135-5bff-8b45-9ab2b514e74c', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', 'natal'),
      ('a1cd5fbc-5dfe-55f6-9df2-c6a448fbfbd0', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', 'panetone')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('8bd594e6-ad92-5963-a458-2345090c682b', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', null, 'recipe', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', 'yield', 'warning', 'A apostila informa rendimento de 5 unidades de 500g, mas também orienta dividir a massa em duas partes. Confirmar o rendimento na revisão.', 90),
      ('addc19d7-4bfb-5eec-b151-e8c15751d9ab', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', null, 'recipe', '7af7c0fc-3c5a-55de-ac5b-372d2d3d0668', 'source_pages', 'warning', 'Paginação baseada na transcrição enviada; conferir no PDF original antes da publicação.', 89)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Panetone de Doce de Leite com Ameixas
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = '1c9854b0-80e8-539a-af7a-579821d382c9')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = '1c9854b0-80e8-539a-af7a-579821d382c9')
     and not exists (select 1 from public.recipe_steps where recipe_id = '1c9854b0-80e8-539a-af7a-579821d382c9') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('3bc0c890-83dc-5dde-80c2-41e8fe958e2f', '1c9854b0-80e8-539a-af7a-579821d382c9', null, 'esponja', 'Esponja', null, null, 1, 1, 81, 82),
      ('a62468ad-451d-5ea2-be9e-a6c7bd2eb325', '1c9854b0-80e8-539a-af7a-579821d382c9', null, 'massa', 'Massa do Panetone', null, null, 1, 2, 81, 82),
      ('92edb1a2-fac7-5428-b113-3c03c3372535', '1c9854b0-80e8-539a-af7a-579821d382c9', null, 'recheio', 'Recheio de Doce de Leite com Ameixa', null, null, 1, 3, 83, 84),
      ('1cb4752b-0c29-5524-993a-9242a2327df4', '1c9854b0-80e8-539a-af7a-579821d382c9', null, 'montagem', 'Montagem — Panetone de Doce de Leite com Ameixas', null, null, 1, 4, 83, 84)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('0294baad-1f7a-5b71-bc22-898ad94974fb', '1c9854b0-80e8-539a-af7a-579821d382c9', '3bc0c890-83dc-5dde-80c2-41e8fe958e2f', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 81, false),
      ('098e8841-88ec-56f3-8145-1b08702dbd08', '1c9854b0-80e8-539a-af7a-579821d382c9', '3bc0c890-83dc-5dde-80c2-41e8fe958e2f', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 81, false),
      ('77ea6462-10af-563b-87b8-3122c65facb5', '1c9854b0-80e8-539a-af7a-579821d382c9', '3bc0c890-83dc-5dde-80c2-41e8fe958e2f', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 81, false),
      ('c733b738-8282-5c25-8ac7-9df9d89fe59c', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 81, false),
      ('eca8eab2-ccef-5bdf-8b26-42f1b680a177', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 81, false),
      ('aa6ea962-2f43-5db1-bbf8-118efff20031', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', null, 3, 5, null, 'colheres (sopa)', null, 'Leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 81, false),
      ('45518997-75e5-5187-b446-3b3b1f7dd774', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 81, false),
      ('c7f5f09c-7d86-512c-a9f0-7e3d24777f33', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 81, false),
      ('6f341e4e-3d1d-5fbe-a6f4-349123c2bd18', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 81, false),
      ('3e86a94a-52ab-52be-bccd-a64961b7a31f', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 81, false),
      ('632d30f7-6798-5cc9-9d15-fe919f0a705a', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 81, false),
      ('a42511ea-c2da-59f0-999d-cbfafeea861c', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 81, false),
      ('711801c9-c69c-559d-8694-afefa3c88488', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 81, false),
      ('c5b38d16-a0d9-5699-ba5a-49ff90854020', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 81, false),
      ('105822a4-d06f-5b04-90e3-6e5ec9061dba', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', '9cf7d3c9-36d9-5e20-9c00-6151636b0ac1', 12, 200, null, 'g', null, 'uvas passas', null, null, 'linear', false, '200g de uvas passas', 81, false),
      ('0d490b6e-5a28-5112-ac0f-6365cb136566', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', '523013e5-3b5c-503c-8e3b-0efe15fa5dda', 13, 200, null, 'g', null, 'frutas cristalizadas', null, null, 'linear', false, '200g de frutas cristalizadas', 81, false),
      ('59c11ff6-7fa1-5da2-b71a-b28db587f54a', '1c9854b0-80e8-539a-af7a-579821d382c9', '92edb1a2-fac7-5428-b113-3c03c3372535', '6b34b876-9b3f-5612-96da-1abcf6f11bbc', 1, 1, null, 'unidade', null, 'leite condensado', null, null, 'linear', false, '1 leite condensado', 83, false),
      ('43483c4f-5b6e-5225-8017-ab12b100cfa6', '1c9854b0-80e8-539a-af7a-579821d382c9', '92edb1a2-fac7-5428-b113-3c03c3372535', '8758d73e-4fcf-508e-940d-635708436a41', 2, 1, null, 'unidade', null, 'creme de leite', null, null, 'linear', false, '1 creme de leite', 83, false),
      ('a145d9c3-734a-5598-945a-4b021f7e3a88', '1c9854b0-80e8-539a-af7a-579821d382c9', '92edb1a2-fac7-5428-b113-3c03c3372535', 'd6023bf0-76f4-5247-899b-d967195f1018', 3, 200, null, 'g', null, 'doce de leite', null, null, 'linear', false, '200g de doce de leite', 83, false),
      ('187235c1-6d65-508a-a91d-69d73944f3cd', '1c9854b0-80e8-539a-af7a-579821d382c9', '92edb1a2-fac7-5428-b113-3c03c3372535', null, 4, 100, null, 'g', null, 'ameixa seca picada', null, null, 'linear', false, '100g de ameixa seca picada', 83, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('37479ef4-8749-51dc-ba9a-2c4b630df962', '1c9854b0-80e8-539a-af7a-579821d382c9', '3bc0c890-83dc-5dde-80c2-41e8fe958e2f', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 82, false),
      ('cf6527f9-66a8-58d4-92da-e6b7bb3932c4', '1c9854b0-80e8-539a-af7a-579821d382c9', '3bc0c890-83dc-5dde-80c2-41e8fe958e2f', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 82, false),
      ('a96da894-015a-5d41-a34f-c86d9bcfc0f3', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 82, false),
      ('b2ba2a57-a8e9-5e5c-a5ea-c254122788db', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 82, false),
      ('1c7a689b-9c48-544c-8381-3727511f95a5', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', 3, 'Acrescente a margarina e sove até atingir o ponto de véu, esticando uma pequena porção até ficar transparente sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 82, false),
      ('1b993a36-3e24-5985-9105-7be4294dc29c', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente. A massa é macia e pegajosa, e suas mãos precisam do óleo para mexer.', null, 82, false),
      ('25023c83-b182-5a28-83ed-1fc7b53b0f10', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', 5, 'Abra a massa em superfície untada com óleo e espalhe as uvas passas e frutas cristalizadas; enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as uvas passas e frutas cristalizadas. Enrole bem e modele formando uma bola', null, 82, false),
      ('7588f166-c759-54a4-8aec-0c723beca204', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', 6, 'Coloque em uma tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 83, false),
      ('7c364aaa-e5e2-5360-98ea-0f2330a3dce5', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', 7, 'Volte para a superfície untada, divida em duas partes do mesmo tamanho e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 83, false),
      ('779c364e-9523-5d90-a56f-5d513b4b7516', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', 8, 'Aguarde a massa crescer até a borda e asse em forno preaquecido a 180 graus por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 83, false),
      ('1293dfbf-83ca-5459-bd04-6c9b078ab10a', '1c9854b0-80e8-539a-af7a-579821d382c9', 'a62468ad-451d-5ea2-be9e-a6c7bd2eb325', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 83, false),
      ('8684c67a-d407-529a-bffb-4748ca48722c', '1c9854b0-80e8-539a-af7a-579821d382c9', '92edb1a2-fac7-5428-b113-3c03c3372535', 1, 'Misture o leite condensado, o creme de leite e o doce de leite em panela de fundo grosso.', 'Misture o leite condensado, o creme de leite e o doce de leite em panela de fundo grosso.', null, 83, false),
      ('2d3e34c8-7725-52ee-8df4-c1fd5b7a6428', '1c9854b0-80e8-539a-af7a-579821d382c9', '92edb1a2-fac7-5428-b113-3c03c3372535', 2, 'Leve ao fogo e mexa em movimentos circulares até engrossar e aparecer o fundo da panela.', 'Leve ao fogo e mexa em movimentos circulares até engrossar e aparecer o fundo da panela.', null, 84, false),
      ('fb5e320b-df5b-5d62-a5e5-bbabd05d746a', '1c9854b0-80e8-539a-af7a-579821d382c9', '92edb1a2-fac7-5428-b113-3c03c3372535', 3, 'Deixe esfriar e misture as ameixas secas picadas.', 'Deixe esfriar e misture as ameixas secas picadas.', null, 84, false),
      ('ff1a5050-63e3-5a54-a1e1-c25e0ae4a7b1', '1c9854b0-80e8-539a-af7a-579821d382c9', '1cb4752b-0c29-5524-993a-9242a2327df4', 1, 'Corte o topo do Panetone e reserve.', 'Comece cortando o topo do Panetone e reserve.', null, 83, false),
      ('be1282d2-c559-5c17-b3c4-a4505647a307', '1c9854b0-80e8-539a-af7a-579821d382c9', '1cb4752b-0c29-5524-993a-9242a2327df4', 2, 'Abra uma cavidade com faca e colher, deixando um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Panetone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Panetone não perder a estrutura e quebrar).', null, 84, false),
      ('dcea4c4a-5268-5a01-acba-f2f83c3d0768', '1c9854b0-80e8-539a-af7a-579821d382c9', '1cb4752b-0c29-5524-993a-9242a2327df4', 3, 'Adicione o recheio com uma colher ou saco de confeitar.', 'Depois adicione o recheio com uma colher ou um saco de confeitar. Finalize com ameixas na parte superior.', null, 84, false),
      ('f25cf60b-96b2-5711-977c-a79e3c4424c7', '1c9854b0-80e8-539a-af7a-579821d382c9', '1cb4752b-0c29-5524-993a-9242a2327df4', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa, quando indicado na receita.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 84, false),
      ('d85daf6c-8dba-5ac8-8eb2-4c5ca749f530', '1c9854b0-80e8-539a-af7a-579821d382c9', '1cb4752b-0c29-5524-993a-9242a2327df4', 5, 'Recoloque a tampa e finalize conforme a decoração indicada na receita.', 'Por último coloque a tampa do seu Panetone/Chocotone e decore da maneira de sua preferência, usando sua criatividade.', null, 84, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('f2dde811-f031-501c-b7fd-051ccecd1219', '1c9854b0-80e8-539a-af7a-579821d382c9', 'natal'),
      ('0cd0856f-f602-5412-aa70-14efb179d9d5', '1c9854b0-80e8-539a-af7a-579821d382c9', 'panetone')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('2b1c01ac-2b26-5ab1-b71a-e278ca0b54e8', '1c9854b0-80e8-539a-af7a-579821d382c9', null, 'recipe', '1c9854b0-80e8-539a-af7a-579821d382c9', 'yield', 'warning', 'A apostila informa rendimento de 5 unidades de 500g, mas também orienta dividir a massa em duas partes. Confirmar o rendimento na revisão.', 82),
      ('d65a21f3-4e18-5d0d-815d-f7d78621c2ef', '1c9854b0-80e8-539a-af7a-579821d382c9', null, 'recipe', '1c9854b0-80e8-539a-af7a-579821d382c9', 'source_pages', 'warning', 'Paginação baseada na transcrição enviada; conferir no PDF original antes da publicação.', 81)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Panetone de Morango
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = 'c10bf956-1f2f-5d22-9dee-b9d01ba27287')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = 'c10bf956-1f2f-5d22-9dee-b9d01ba27287')
     and not exists (select 1 from public.recipe_steps where recipe_id = 'c10bf956-1f2f-5d22-9dee-b9d01ba27287') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('94aaff14-3e0b-5a1f-988b-fbd27aafd1f9', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', null, 'esponja', 'Esponja', null, null, 1, 1, 41, 42),
      ('f93f9d91-45e6-5c37-8d6c-3a3f8013a461', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', null, 'massa', 'Massa do Panetone', null, null, 1, 2, 41, 42),
      ('47010081-2459-5215-b7a2-ab56817870ad', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', null, 'recheio', 'Recheio de Morango', null, null, 1, 3, 43, 44),
      ('eacb4d3d-2af3-5311-aef0-f758da367526', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', null, 'montagem', 'Montagem — Panetone de Morango', null, null, 1, 4, 43, 44)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('3f851c3f-52b8-57cd-9e28-974a60bd4b81', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', '94aaff14-3e0b-5a1f-988b-fbd27aafd1f9', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 41, false),
      ('7c9496ba-0df3-5a11-a5ad-bec3a1f5554e', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', '94aaff14-3e0b-5a1f-988b-fbd27aafd1f9', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 41, false),
      ('f23d50f9-9534-54fd-99c8-6191cd56af45', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', '94aaff14-3e0b-5a1f-988b-fbd27aafd1f9', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 41, false),
      ('b5603995-3b36-5836-9a1a-cf3673d027f5', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 41, false),
      ('59216895-aaa2-587a-8584-9c1f12360bb0', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 41, false),
      ('87fb7b51-3b09-5cb8-8740-3c45085396b0', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', null, 3, 5, null, 'colheres (sopa)', null, 'Leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 41, false),
      ('e9baa3ad-ce3c-546a-9dbc-98e086315ab0', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 41, false),
      ('27c4a992-3ffa-57c9-b7b5-0c7402f76cdf', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 41, false),
      ('3f603060-cc59-5c18-a474-b90db0f156da', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 41, false),
      ('8de9c1a9-476e-5c30-96b2-2db4159037bf', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 41, false),
      ('d669adb2-37bf-5874-a0eb-228711c2c5f8', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 41, false),
      ('7431e66e-ada8-5a6a-864a-ad63f2e4180a', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 41, false),
      ('1876e417-ba19-5204-a479-91edf1120dd2', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 41, false),
      ('f74ad4a3-47e7-5a89-ad80-19d8bde07471', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 41, false),
      ('f65f46b1-8cba-523d-ae42-61fef500400b', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', '9cf7d3c9-36d9-5e20-9c00-6151636b0ac1', 12, 200, null, 'g', null, 'uvas passas', null, null, 'linear', false, '200g de uvas passas', 41, false),
      ('b8254c53-3078-54ad-adbd-0e873f90b994', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', '523013e5-3b5c-503c-8e3b-0efe15fa5dda', 13, 250, null, 'g', null, 'frutas cristalizadas', null, null, 'linear', false, '250g de frutas cristalizadas', 41, false),
      ('26bdcb17-2333-58bf-88b6-2ace2043e796', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', '47010081-2459-5215-b7a2-ab56817870ad', '6b34b876-9b3f-5612-96da-1abcf6f11bbc', 1, 1, null, 'unidade', null, 'leite condensado', null, null, 'linear', false, '1 leite condensado', 43, false),
      ('2be87bdb-37b9-56e9-bc5e-08c368c9ce1b', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', '47010081-2459-5215-b7a2-ab56817870ad', '8758d73e-4fcf-508e-940d-635708436a41', 2, 1, null, 'unidade', null, 'creme de leite', null, null, 'linear', false, '1 creme de leite', 43, false),
      ('2215ca63-5dd3-53a1-a90c-5782cfbed3af', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', '47010081-2459-5215-b7a2-ab56817870ad', '40245c07-39b0-5a2c-b610-edc6bb3fb56b', 3, 50, null, 'g', null, 'chocolate branco', null, null, 'linear', false, '50g chocolate branco', 43, false),
      ('5b9610c8-261b-5694-aeca-8ed5832a4a7f', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', '47010081-2459-5215-b7a2-ab56817870ad', null, 4, 2, null, 'colheres (sopa)', null, 'pó saborizante de morango Mavalério', null, null, 'linear', false, '2 colheres (sopa) de pó saborizante de morango da Mavalério', 43, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('37d8be8d-ce99-543f-934d-31c5ade7d652', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', '94aaff14-3e0b-5a1f-988b-fbd27aafd1f9', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 42, false),
      ('530705f3-7098-5654-bb1b-225191abe06b', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', '94aaff14-3e0b-5a1f-988b-fbd27aafd1f9', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 42, false),
      ('3a7c5e5b-b1a8-59e6-aa46-321e0f60cfba', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 42, false),
      ('e5cfa67e-864b-55af-96a6-a8308cc059a0', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 42, false),
      ('d56e983e-6b39-5424-866e-598758fe1dad', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', 3, 'Acrescente a margarina e sove até atingir o ponto de véu, esticando uma pequena porção até ficar transparente sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 42, false),
      ('41121353-d276-5bd0-a865-2e430748ed57', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente. A massa é macia e pegajosa, e suas mãos precisam do óleo para mexer.', null, 42, false),
      ('7571092f-69e9-5ecc-8642-0a8572f9b911', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', 5, 'Abra a massa em superfície untada com óleo e espalhe as frutas cristalizadas e as uvas passas; enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as frutas cristalizadas e as uvas passas. Enrole bem e modele formando uma bola', null, 42, false),
      ('af0a8bf8-136e-5b3b-921a-5f26c1f18673', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', 6, 'Coloque em uma tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 43, false),
      ('c8c720ad-46c1-5250-98e9-26c07e5d6ab8', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', 7, 'Volte para a superfície untada, divida em duas partes do mesmo tamanho e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 43, false),
      ('e60ae8ce-cc79-52c5-a8ac-af4c81c3c5df', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', 8, 'Aguarde a massa crescer até a borda e asse em forno preaquecido a 180 graus por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 43, false),
      ('e5777594-b9af-58b6-b3ce-fc91387ef3b5', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'f93f9d91-45e6-5c37-8d6c-3a3f8013a461', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 43, false),
      ('3ef7a5ce-71bb-50ad-8b36-19c33455ed19', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', '47010081-2459-5215-b7a2-ab56817870ad', 1, 'Misture todos os ingredientes em uma panela.', 'Misture todos os ingredientes em uma panela.', null, 43, false),
      ('858afe7a-0823-50e3-8c94-033e40ab72a7', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', '47010081-2459-5215-b7a2-ab56817870ad', 2, 'Leve ao fogo baixo, mexendo até desgrudar por completo do fundo da panela. Deixe esfriar.', 'Leve ao fogo baixo, mexendo até desgrudar por completo do fundo da panela. Deixe esfriar.', null, 44, false),
      ('84addc7e-45a3-590f-a8ef-953d9e2e15d6', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'eacb4d3d-2af3-5311-aef0-f758da367526', 1, 'Corte o topo do Panetone e reserve.', 'Comece cortando o topo do Panetone e reserve.', null, 43, false),
      ('60876773-2e1a-54d3-9941-e175b4a2dee3', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'eacb4d3d-2af3-5311-aef0-f758da367526', 2, 'Abra uma cavidade com faca e colher, deixando um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Panetone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Panetone não perder a estrutura e quebrar).', null, 44, false),
      ('8237c1df-0192-50c6-b322-08656f9e3c30', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'eacb4d3d-2af3-5311-aef0-f758da367526', 3, 'Adicione o recheio com uma colher ou saco de confeitar.', 'Depois adicione o recheio com uma colher ou um saco de confeitar. Decore com morangos (opcional).', null, 44, false),
      ('44c65360-72b0-5873-8d7a-c0c6de38007c', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'eacb4d3d-2af3-5311-aef0-f758da367526', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa, quando indicado na receita.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 44, false),
      ('85de5f05-09fa-5be2-abfb-f341f1976c31', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'eacb4d3d-2af3-5311-aef0-f758da367526', 5, 'Recoloque a tampa e finalize conforme a decoração indicada na receita.', 'Por último coloque a tampa do seu Panetone/Chocotone e decore da maneira de sua preferência, usando sua criatividade.', null, 44, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('864b6782-2af5-5ea6-9108-589222bca371', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'natal'),
      ('37e43389-2118-51ab-990d-c9fa0f395850', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'panetone')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('f5f4edd4-a74c-57ba-b350-16463dac5e96', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', null, 'recipe', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'yield', 'warning', 'A apostila informa rendimento de 5 unidades de 500g, mas também orienta dividir a massa em duas partes. Confirmar o rendimento na revisão.', 42),
      ('72d968e8-db6d-5e48-98a9-2c431271ab95', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', null, 'recipe', 'c10bf956-1f2f-5d22-9dee-b9d01ba27287', 'source_pages', 'warning', 'Paginação baseada na transcrição enviada; conferir no PDF original antes da publicação.', 41)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Panetone de Nozes
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = '6a8c669b-816b-5cf2-9774-2d16d24209bb')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = '6a8c669b-816b-5cf2-9774-2d16d24209bb')
     and not exists (select 1 from public.recipe_steps where recipe_id = '6a8c669b-816b-5cf2-9774-2d16d24209bb') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('9b38a55c-e476-5a76-a7ce-db4b23017aea', '6a8c669b-816b-5cf2-9774-2d16d24209bb', null, 'esponja', 'Esponja', null, null, 1, 1, 77, 78),
      ('fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', '6a8c669b-816b-5cf2-9774-2d16d24209bb', null, 'massa', 'Massa do Panetone', null, null, 1, 2, 77, 78),
      ('f1214e22-8899-5be1-9c24-ac212aef27f8', '6a8c669b-816b-5cf2-9774-2d16d24209bb', null, 'recheio', 'Recheio de Brigadeiro Branco com Nozes', null, null, 1, 3, 79, 80),
      ('40193407-cab4-589d-a194-7b6deec49718', '6a8c669b-816b-5cf2-9774-2d16d24209bb', null, 'montagem', 'Montagem — Panetone de Nozes', null, null, 1, 4, 79, 80)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('2c787095-1942-5d91-8a4c-09b58aee1c84', '6a8c669b-816b-5cf2-9774-2d16d24209bb', '9b38a55c-e476-5a76-a7ce-db4b23017aea', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 77, false),
      ('75752dae-4214-5b05-a891-00ef4594feb0', '6a8c669b-816b-5cf2-9774-2d16d24209bb', '9b38a55c-e476-5a76-a7ce-db4b23017aea', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 77, false),
      ('c8bb8f7b-3e1a-54a9-8446-fa7fd22ab512', '6a8c669b-816b-5cf2-9774-2d16d24209bb', '9b38a55c-e476-5a76-a7ce-db4b23017aea', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 77, false),
      ('646efad8-ffa3-5773-8828-4865ccc78ce8', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 77, false),
      ('2a6f2fdb-3449-5c2c-8891-c10997830bed', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 77, false),
      ('c48e3b63-3fb2-5b06-99ac-548a4337572f', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', null, 3, 5, null, 'colheres (sopa)', null, 'Leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 77, false),
      ('8e3f2260-9d76-5911-8f66-a77f4fa69886', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 77, false),
      ('62005577-4f34-5703-a21e-3589989257c8', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 77, false),
      ('2892ba7a-a477-512a-b845-cf5dbadea20a', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 77, false),
      ('aa086006-8925-568c-9b0d-57d5948f8e00', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 77, false),
      ('a6512267-662e-50e9-b4bc-bd9199775d4f', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 77, false),
      ('354db7b9-9db0-5940-b7dd-234adc1df1f4', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 77, false),
      ('de0716c3-7602-5452-be87-800ce11a871b', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 77, false),
      ('0f01a43f-29f7-55f1-af7f-f79dafb71cb3', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 77, false),
      ('bad7cd57-2451-5369-9eda-ceed44d446f8', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', '045392ee-ad51-52cf-9c5b-2f4e819896df', 12, 350, null, 'g', null, 'nozes picadas', null, null, 'linear', false, '350g de nozes picadas', 77, false),
      ('9e8ecfe1-a50e-5f30-886d-5939542d554a', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'f1214e22-8899-5be1-9c24-ac212aef27f8', '6b34b876-9b3f-5612-96da-1abcf6f11bbc', 1, 1, null, 'unidade', null, 'leite condensado', null, null, 'linear', false, '1 leite condensado', 79, false),
      ('04e59147-c6a2-50d4-8e14-bb6a31c553e5', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'f1214e22-8899-5be1-9c24-ac212aef27f8', '8758d73e-4fcf-508e-940d-635708436a41', 2, 1, null, 'unidade', null, 'creme de leite', null, null, 'linear', false, '1 creme de leite', 79, false),
      ('5971d218-760e-5092-835d-97a1e6b0d284', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'f1214e22-8899-5be1-9c24-ac212aef27f8', '045392ee-ad51-52cf-9c5b-2f4e819896df', 3, 100, null, 'g', null, 'nozes picadas', null, null, 'linear', false, '100g de Nozes picadas', 79, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('31114b0e-98e8-5c27-a8c1-1e427307b86e', '6a8c669b-816b-5cf2-9774-2d16d24209bb', '9b38a55c-e476-5a76-a7ce-db4b23017aea', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 78, false),
      ('89ac28b0-5236-54b3-9eb8-3ba4f4868a2d', '6a8c669b-816b-5cf2-9774-2d16d24209bb', '9b38a55c-e476-5a76-a7ce-db4b23017aea', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 78, false),
      ('949382e7-07f9-5eef-ace3-8c5bc7e3e97c', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 78, false),
      ('b4e37d3f-d9a3-5106-803e-1ca01e6cd6f6', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 78, false),
      ('ba02482c-25b4-5faa-9af7-cf1cac142568', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', 3, 'Acrescente a margarina e sove até atingir o ponto de véu, esticando uma pequena porção até ficar transparente sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 78, false),
      ('31b4ffe5-749e-55d1-9ea9-1f08119404f1', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente. A massa é macia e pegajosa, e suas mãos precisam do óleo para mexer.', null, 78, false),
      ('c5b54513-898f-5711-97b0-cb63578a96a4', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', 5, 'Abra a massa em superfície untada com óleo e espalhe as nozes picadas; enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as nozes picadas. Enrole bem e modele formando uma bola', null, 78, false),
      ('ec298b5a-79c5-5c08-b0be-a71f7c59790a', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', 6, 'Coloque em uma tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 79, false),
      ('c8bbdbc8-c83f-5c9c-bf3d-24e393799647', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', 7, 'Volte para a superfície untada, divida em duas partes do mesmo tamanho e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 79, false),
      ('fdb52ec7-9938-5d59-a07e-4295a0de4d52', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', 8, 'Aguarde a massa crescer até a borda e asse em forno preaquecido a 180 graus por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 79, false),
      ('01980b80-8ff9-5e90-8183-49a0cc6286b8', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'fa54a60f-31ef-5e0a-a912-3f3e1394b7d7', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 79, false),
      ('99cec57b-7946-5993-9115-465dfc01b8e0', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'f1214e22-8899-5be1-9c24-ac212aef27f8', 1, 'Misture o leite condensado e o creme de leite em panela de fundo grosso.', 'Misture o leite condensado e o creme de leite em panela de fundo grosso.', null, 79, false),
      ('8bb20939-c2ee-5172-8ff5-3c344f7c18b4', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'f1214e22-8899-5be1-9c24-ac212aef27f8', 2, 'Leve ao fogo e mexa em movimentos circulares até engrossar e aparecer o fundo da panela.', 'Leve ao fogo e mexa em movimentos circulares até engrossar e aparecer o fundo da panela.', null, 80, false),
      ('8d93c38e-ca2b-5474-9a79-810ee9a23815', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'f1214e22-8899-5be1-9c24-ac212aef27f8', 3, 'Deixe esfriar e misture as nozes picadas.', 'Deixe esfriar e misture as nozes picadas.', null, 80, false),
      ('d2d26388-b1ff-5f7b-9164-7f6e4c5a0703', '6a8c669b-816b-5cf2-9774-2d16d24209bb', '40193407-cab4-589d-a194-7b6deec49718', 1, 'Corte o topo do Panetone e reserve.', 'Comece cortando o topo do Panetone e reserve.', null, 79, false),
      ('f1bb94f7-e79f-5c82-958a-c48131139c1d', '6a8c669b-816b-5cf2-9774-2d16d24209bb', '40193407-cab4-589d-a194-7b6deec49718', 2, 'Abra uma cavidade com faca e colher, deixando um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Panetone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Panetone não perder a estrutura e quebrar).', null, 80, false),
      ('8038991d-6036-507d-b43f-d87adf71cbc0', '6a8c669b-816b-5cf2-9774-2d16d24209bb', '40193407-cab4-589d-a194-7b6deec49718', 3, 'Adicione o recheio com uma colher ou saco de confeitar.', 'Depois adicione o recheio com uma colher ou um saco de confeitar. Finalize com nozes na parte superior.', null, 80, false),
      ('3103d89c-3c52-5af3-bf04-93f07f09a0c9', '6a8c669b-816b-5cf2-9774-2d16d24209bb', '40193407-cab4-589d-a194-7b6deec49718', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa, quando indicado na receita.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 80, false),
      ('d0c7b797-c9b0-54c6-ab39-82379f4507be', '6a8c669b-816b-5cf2-9774-2d16d24209bb', '40193407-cab4-589d-a194-7b6deec49718', 5, 'Recoloque a tampa e finalize conforme a decoração indicada na receita.', 'Por último coloque a tampa do seu Panetone/Chocotone e decore da maneira de sua preferência, usando sua criatividade.', null, 80, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('38a671de-5b06-51ee-80c0-f49725013df6', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'natal'),
      ('2dc453b0-609a-5f8e-a8f0-f97f56d57f96', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'panetone')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('59126de3-43cd-579e-88e4-8ae11faa0221', '6a8c669b-816b-5cf2-9774-2d16d24209bb', null, 'recipe', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'yield', 'warning', 'A apostila informa rendimento de 5 unidades de 500g, mas também orienta dividir a massa em duas partes. Confirmar o rendimento na revisão.', 78),
      ('643b7db1-611f-5334-90ba-1a0173cef980', '6a8c669b-816b-5cf2-9774-2d16d24209bb', null, 'recipe', '6a8c669b-816b-5cf2-9774-2d16d24209bb', 'source_pages', 'warning', 'Paginação baseada na transcrição enviada; conferir no PDF original antes da publicação.', 77)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Panetone Red Velvet com Recheio de Limão
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = 'd4a503e9-6658-5cc1-9ff8-f27a4f989268')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = 'd4a503e9-6658-5cc1-9ff8-f27a4f989268')
     and not exists (select 1 from public.recipe_steps where recipe_id = 'd4a503e9-6658-5cc1-9ff8-f27a4f989268') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('7405d144-f7e2-5af3-aae6-0155198c3928', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', null, 'esponja', 'Esponja', null, null, 1, 1, 105, 106),
      ('9c954082-c017-5de1-b4bb-34789ba980b0', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', null, 'massa', 'Massa do Panetone', null, null, 1, 2, 105, 106),
      ('0452b2d0-cdc7-5244-94aa-3f9dddb6ec9c', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', null, 'recheio', 'Recheio de Limão', null, null, 1, 3, 107, 108),
      ('49387e95-a29a-5af3-bd23-d4403877937c', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', null, 'montagem', 'Montagem — Panetone Red Velvet com Recheio de Limão', null, null, 1, 4, 107, 108)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('f147d200-5bb9-5db2-9c12-3f9dbf73ce6c', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '7405d144-f7e2-5af3-aae6-0155198c3928', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 105, false),
      ('074bf293-723e-55da-a0dd-ef7f9e9b8b3b', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '7405d144-f7e2-5af3-aae6-0155198c3928', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 105, false),
      ('3c3ac034-778d-5d98-af99-189fb1aa775e', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '7405d144-f7e2-5af3-aae6-0155198c3928', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 105, false),
      ('aa3c3d1f-1292-5fe5-aad2-a6e2b3675df7', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 105, false),
      ('a60f207b-5964-5558-9d0a-6bed9b45cad9', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 105, false),
      ('4114dc44-d960-5b10-9210-85be8ab22f00', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', null, 3, 5, null, 'colheres (sopa)', null, 'Leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 105, false),
      ('6f7120c6-94d5-5b2b-a288-e5106fd8a573', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 105, false),
      ('242e2961-05be-5099-81de-dc8200dfb8de', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 105, false),
      ('967dc6ec-37f3-5bde-b652-bc10c7d28822', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 105, false),
      ('cd22d4ce-c65c-5a95-bf8f-5ea1a3dd5fbb', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 105, false),
      ('314c3fc4-dada-5c15-afbc-07666619069e', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 105, false),
      ('3365aa92-eda5-55f0-b72c-bbc0f6ef39be', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 105, false),
      ('87a77f64-51b1-5b4c-a856-04ac0f71465e', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 105, false),
      ('a786ba7d-8e52-5034-9748-d2adda77f67d', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 105, false),
      ('c3d31601-4fa8-57cd-8c56-cd513b7582f7', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', '9cf7d3c9-36d9-5e20-9c00-6151636b0ac1', 12, 200, null, 'g', null, 'uvas passas', null, null, 'linear', false, '200g de uvas passas', 105, false),
      ('caf422cb-e497-5e2d-91ca-dbae8ab8c604', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', '523013e5-3b5c-503c-8e3b-0efe15fa5dda', 13, 250, null, 'g', null, 'frutas cristalizadas', null, null, 'linear', false, '250g de frutas cristalizadas', 105, false),
      ('a01cffa1-1db0-5e66-820e-8d59cc78ff75', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', null, 14, 30, null, 'g', null, 'corante em gel vermelho morango Mix', null, null, 'linear', false, '30g de corante em gel vermelho morango (recomendo a marca Mix)', 105, false),
      ('b1aaa780-acb3-59ea-a458-5e981ac7ff2c', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '0452b2d0-cdc7-5244-94aa-3f9dddb6ec9c', '6b34b876-9b3f-5612-96da-1abcf6f11bbc', 1, 1, null, 'unidade', null, 'leite condensado', null, null, 'linear', false, '1 leite condensado', 107, false),
      ('b30493e1-67ae-5fce-9e77-56ae50cf2903', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '0452b2d0-cdc7-5244-94aa-3f9dddb6ec9c', '8758d73e-4fcf-508e-940d-635708436a41', 2, 1, null, 'unidade', null, 'creme de leite', null, null, 'linear', false, '1 creme de leite', 107, false),
      ('71f63f25-302e-5be1-85a6-89efd8e615f5', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '0452b2d0-cdc7-5244-94aa-3f9dddb6ec9c', null, 3, 100, null, 'ml', null, 'suco de limão', null, null, 'linear', false, '100ml de suco de limão', 107, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('120f11ab-2112-5f9e-915f-695795131de5', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '7405d144-f7e2-5af3-aae6-0155198c3928', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 106, false),
      ('8d0043b4-7d1e-5a18-91a1-cbb3dc6cc451', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '7405d144-f7e2-5af3-aae6-0155198c3928', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 106, false),
      ('712b1a96-ef9a-550d-ab65-14a8ec669195', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 106, false),
      ('35638489-f877-584f-9a31-9a5d1fd5b4a8', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida, sove por cerca de 10 minutos e adicione aos poucos o corante vermelho.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 106, false),
      ('2ef390d1-cef8-5aad-8cd0-1401e6564463', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', 3, 'Acrescente a margarina e sove até atingir o ponto de véu, esticando uma pequena porção até ficar transparente sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 106, false),
      ('e96b951c-975b-5fe3-bb3f-b20bd9fc1fb3', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente. A massa é macia e pegajosa, e suas mãos precisam do óleo para mexer.', null, 106, false),
      ('5e4d3db8-4e75-512a-88ac-65bcb81b5c0a', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', 5, 'Abra a massa em superfície untada com óleo e espalhe as uvas passas e as frutas cristalizadas; enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as uvas passas e as frutas cristalizadas. Enrole bem e modele formando uma bola', null, 106, false),
      ('04f19d6f-addb-552a-aa83-1130ad168371', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', 6, 'Coloque em uma tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 107, false),
      ('9230cc51-0fa4-5bc3-b495-4aebcb8fe2eb', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', 7, 'Volte para a superfície untada, divida em duas partes do mesmo tamanho e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 107, false),
      ('6c8035ed-9b86-5ed8-856f-134a896fe282', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', 8, 'Aguarde a massa crescer até a borda e asse em forno preaquecido a 180 graus por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 107, false),
      ('ecc3ab12-cd38-5bb9-a6f8-80cd9fbfad55', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '9c954082-c017-5de1-b4bb-34789ba980b0', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 107, false),
      ('8e6a7f0f-2d84-53f2-b6f4-b040879be4c8', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '0452b2d0-cdc7-5244-94aa-3f9dddb6ec9c', 1, 'Misture o leite condensado e o creme de leite em panela de fundo grosso e leve ao fogo médio, mexendo por aproximadamente 10 minutos ou até engrossar um pouco.', 'Misture o leite condensado e o creme de leite em panela de fundo grosso e leve ao fogo médio, mexendo por aproximadamente 10 minutos ou até engrossar um pouco.', null, 107, false),
      ('1d71ddac-6896-5fd4-8898-e852f615e874', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '0452b2d0-cdc7-5244-94aa-3f9dddb6ec9c', 2, 'Deixe esfriar e acrescente o suco de limão, misturando bem com uma colher.', 'Deixe esfriar e acrescente o suco de limão, misturando bem com uma colher.', null, 108, false),
      ('c490bc3a-2b43-507a-8e63-72241f6f9da8', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '0452b2d0-cdc7-5244-94aa-3f9dddb6ec9c', 3, 'A dica permite substituir o suco por pasta saborizante ou pó saborizante da Mavalério, acrescentando em média 2 colheres de café bem cheias.', 'A dica permite substituir o suco por pasta saborizante ou pó saborizante da Mavalério, acrescentando em média 2 colheres de café bem cheias.', null, 108, false),
      ('bd61a2ff-b830-5d65-a19f-fd537de539f9', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '49387e95-a29a-5af3-bd23-d4403877937c', 1, 'Corte o topo do Panetone e reserve.', 'Comece cortando o topo do Panetone e reserve.', null, 107, false),
      ('ae35e1cf-4e87-529e-8387-349d23fef2ba', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '49387e95-a29a-5af3-bd23-d4403877937c', 2, 'Abra uma cavidade com faca e colher, deixando um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Panetone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Panetone não perder a estrutura e quebrar).', null, 108, false),
      ('4d84b429-87f9-5bca-b748-64b56556de80', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '49387e95-a29a-5af3-bd23-d4403877937c', 3, 'Adicione o recheio com uma colher ou saco de confeitar.', 'Depois adicione o recheio com uma colher ou um saco de confeitar. Finalize com um pouco do recheio e raspas de limão.', null, 108, false),
      ('d5303dda-da84-54c4-875b-fa1840190a13', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '49387e95-a29a-5af3-bd23-d4403877937c', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa, quando indicado na receita.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 108, false),
      ('de7aa5dd-ee20-57b9-bd67-08375fdaf061', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', '49387e95-a29a-5af3-bd23-d4403877937c', 5, 'Recoloque a tampa e finalize conforme a decoração indicada na receita.', 'Por último coloque a tampa do seu Panetone/Chocotone e decore da maneira de sua preferência, usando sua criatividade.', null, 108, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('f1adc426-69a8-558b-99b4-9b5ef2cec371', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', 'natal'),
      ('3a5ff71f-5a30-5e64-95c5-6009fa66d7f3', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', 'panetone')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('a33cc406-74f2-5c75-80d8-e5dc8787723b', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', null, 'recipe', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', 'yield', 'warning', 'A apostila informa rendimento de 5 unidades de 500g, mas também orienta dividir a massa em duas partes. Confirmar o rendimento na revisão.', 106),
      ('8071eeca-11b7-5862-a849-103be7f4e31e', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', null, 'recipe', 'd4a503e9-6658-5cc1-9ff8-f27a4f989268', 'source_pages', 'warning', 'Paginação baseada na transcrição enviada; conferir no PDF original antes da publicação.', 105)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Panetone Tradicional
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = 'd2ff7c98-1883-52ee-8f1d-b725b581dca4')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = 'd2ff7c98-1883-52ee-8f1d-b725b581dca4')
     and not exists (select 1 from public.recipe_steps where recipe_id = 'd2ff7c98-1883-52ee-8f1d-b725b581dca4') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('e3d3501e-2742-5d77-bc3d-5491fd917714', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', null, 'esponja', 'Esponja', null, null, 1, 1, 18, 19),
      ('c095b1e0-0765-5587-9a29-1ead3717dc42', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', null, 'massa', 'Massa do Panetone', null, null, 1, 2, 18, 20),
      ('66efa8f3-251f-5952-9256-f0f5dbdb0db3', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', null, 'finalizacao', 'Finalização e forno', null, null, 1, 3, 20, 20)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('3978c93d-4186-552e-b002-872bb7b7bd53', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'e3d3501e-2742-5d77-bc3d-5491fd917714', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 18, false),
      ('5f2b1161-48d8-52f2-bdb4-800394ad43d4', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'e3d3501e-2742-5d77-bc3d-5491fd917714', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 18, false),
      ('6c02686b-d6ba-564d-a5bb-84b3d1376862', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'e3d3501e-2742-5d77-bc3d-5491fd917714', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 18, false),
      ('f0fa3481-8300-573b-89f1-6caeca6c209e', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'c095b1e0-0765-5587-9a29-1ead3717dc42', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 18, false),
      ('0456645c-d5e8-5643-bdf9-a6ca37969a08', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'c095b1e0-0765-5587-9a29-1ead3717dc42', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 18, false),
      ('411f5df8-2d25-5ac2-9c5f-8aa39bab69e0', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'c095b1e0-0765-5587-9a29-1ead3717dc42', '9b1e65ad-f9ce-50fa-aa1c-9d934b76e83c', 3, 5, null, 'colheres (sopa)', null, 'leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 18, false),
      ('65671fa8-3cca-5796-a3ce-e7aca765dade', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'c095b1e0-0765-5587-9a29-1ead3717dc42', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 18, false),
      ('1e980d7e-cd1b-5925-a816-b33d681b7459', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'c095b1e0-0765-5587-9a29-1ead3717dc42', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 18, false),
      ('3d45f3f5-f4b9-5bc6-a18d-d64ef5c8df9b', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'c095b1e0-0765-5587-9a29-1ead3717dc42', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 18, false),
      ('93079fac-a5bb-5994-8821-52f924d2d4b5', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'c095b1e0-0765-5587-9a29-1ead3717dc42', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 18, false),
      ('633e6942-318f-5787-8e00-134d83565c0d', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'c095b1e0-0765-5587-9a29-1ead3717dc42', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 18, false),
      ('26b83065-dd09-5052-b863-237cb0bc4646', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'c095b1e0-0765-5587-9a29-1ead3717dc42', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 18, false),
      ('7b051aae-c80a-51b9-b8ab-f5d2eaa7447a', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'c095b1e0-0765-5587-9a29-1ead3717dc42', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 18, false),
      ('8e3e47c6-4817-51a8-825c-d6a11b71e63c', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'c095b1e0-0765-5587-9a29-1ead3717dc42', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 18, false),
      ('5de1ae03-dfbc-591f-b116-a7007b7a0f62', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'c095b1e0-0765-5587-9a29-1ead3717dc42', '9cf7d3c9-36d9-5e20-9c00-6151636b0ac1', 12, 200, null, 'g', null, 'uvas-passas', null, null, 'linear', false, '200g de uvas passas + 250g de frutas cristalizadas', 18, false),
      ('60a0641e-e1ef-5dad-958c-3d9ff73a54ad', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'c095b1e0-0765-5587-9a29-1ead3717dc42', '523013e5-3b5c-503c-8e3b-0efe15fa5dda', 13, 250, null, 'g', null, 'frutas cristalizadas', null, null, 'linear', false, '200g de uvas passas + 250g de frutas cristalizadas', 18, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('8f11cd54-e7ee-58d5-a71b-ef2be3b96262', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'e3d3501e-2742-5d77-bc3d-5491fd917714', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 19, false),
      ('ea48030d-75fa-5c06-8976-458bf68523f3', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'e3d3501e-2742-5d77-bc3d-5491fd917714', 2, 'Cubra bem e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 19, false),
      ('ac6c9a7f-a48e-5b61-bf07-3599daf56ed1', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'c095b1e0-0765-5587-9a29-1ead3717dc42', 1, 'Em uma vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 19, false),
      ('4815b268-c59a-5922-bafa-36416bec663b', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'c095b1e0-0765-5587-9a29-1ead3717dc42', 2, 'Em outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja já descansada, até formar uma farofa. Despeje a farofa na mistura líquida de água com as essências e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 19, false),
      ('c69aaa69-7212-5c85-b38a-24cdbdc1f3b3', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'c095b1e0-0765-5587-9a29-1ead3717dc42', 3, 'Acrescente a margarina e sove até chegar ao ponto de véu: a massa deve abrir até ficar transparente, sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 19, false),
      ('88afa88f-6b36-559f-b652-e12d8ad17501', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'c095b1e0-0765-5587-9a29-1ead3717dc42', 4, 'Adicione as raspas de limão e laranja e mexa até incorporar totalmente. A massa é macia e pegajosa; use óleo nas mãos para mexer.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente. A massa é macia e pegajosa, e suas mãos precisam do óleo para mexer.', null, 19, false),
      ('01c7ea6e-3dc9-55ad-996d-c1d05674d1a1', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'c095b1e0-0765-5587-9a29-1ead3717dc42', 5, 'Coloque a massa em uma superfície untada com óleo, abra com as mãos, espalhe as frutas cristalizadas e as uvas-passas, enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as frutas cristalizadas e as uvas passas. Enrole bem e modele formando uma bola', null, 19, false),
      ('a24f069f-a7fb-536d-95bc-f2a2f8779214', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'c095b1e0-0765-5587-9a29-1ead3717dc42', 6, 'Coloque em uma tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 20, false),
      ('3695ada8-478f-57e7-9568-a8f8523f751a', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'c095b1e0-0765-5587-9a29-1ead3717dc42', 7, 'Volte a massa para a superfície untada e divida em duas partes do mesmo tamanho. Coloque nas formas de papel; a massa deve ficar até a metade da forma.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 20, false),
      ('b2c82fb8-2a22-5700-9225-de78c52b10ca', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'c095b1e0-0765-5587-9a29-1ead3717dc42', 8, 'Aguarde a massa crescer até a borda e asse em forno preaquecido a 180°C por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 20, false),
      ('cffcc23f-04a2-5eec-b575-6935a70aeab2', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', '66efa8f3-251f-5952-9256-f0f5dbdb0db3', 1, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 20, false)
    on conflict (id) do nothing;
    insert into public.recipe_notes (id, recipe_id, kind, title, body, original_text, source_page, position) values
      ('1578e4f6-382c-5908-ad7b-5a51f6b9b40b', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'tip', null, 'Opcionalmente, coloque uma forma retangular com água na grade de baixo para deixar o forno úmido e ajudar a massa a ficar fofinha e não endurecer facilmente depois.', 'DICA ESPECIAL E OPCIONAL: Coloque uma forma retangular com água na grade de baixo para deixar o forno úmido para que a massa fique fofinha e não endureça facilmente depois.', 20, 1),
      ('bb466818-0552-5b71-9ed1-fa3b3d22c2c2', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'equipment', null, 'Balança', null, 8, 1),
      ('907ea02c-cc58-57e4-9cfa-46c8d3ddd54a', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'equipment', null, 'Copo medidor', null, 8, 2),
      ('5cfad510-dc2a-5a64-869f-f44fab84ca0b', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'equipment', null, 'Espátula de silicone e rígida', null, 8, 3),
      ('319f46d6-a340-503d-abfe-d666ac9d9444', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'equipment', null, 'Formas de papel para Panetone de 500g (13cm x 9,5cm)', null, 9, 4),
      ('dce3337c-de0f-53b0-b6d3-8fe40231ca90', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'equipment', null, 'Grade para esfriar', null, 9, 5)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('10d99681-c914-5e35-b352-ab232371f84c', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'natal'),
      ('039d9dce-d74a-59a0-b2ce-f1077c81ba12', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'panetone'),
      ('5472b35d-7205-557d-b55e-bce344c25244', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'frutas-cristalizadas')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('73f10309-755a-5e74-9153-cd789fd8967d', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', null, 'recipe', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'yield', 'warning', 'O texto informa rendimento de 5 Panetones de 500g, mas também orienta dividir a massa em duas partes. Confirmar esse rendimento na revisão.', 20),
      ('bcb7eed3-bc63-52c0-8756-a63d6bf9ebbb', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', null, 'recipe', 'd2ff7c98-1883-52ee-8f1d-b725b581dca4', 'source_pages', 'warning', 'As páginas são as apresentadas na transcrição enviada nesta conversa; conferir a paginação no PDF original antes da publicação.', 18)
    on conflict (id) do nothing;
  end if;
end $ficha$;

-- Ficha: Panetone Trufado de Maracujá
-- (só é carregada se a receita ainda não tiver partes, ingredientes ou etapas no banco)
do $ficha$
begin
  if not exists (select 1 from public.recipe_components where recipe_id = 'f162e20a-72c7-544c-b8dc-77abfd74956a')
     and not exists (select 1 from public.recipe_ingredients where recipe_id = 'f162e20a-72c7-544c-b8dc-77abfd74956a')
     and not exists (select 1 from public.recipe_steps where recipe_id = 'f162e20a-72c7-544c-b8dc-77abfd74956a') then
    insert into public.recipe_components (id, recipe_id, linked_recipe_id, role, title, original_title, description, multiplier, position, source_page_start, source_page_end) values
      ('fceb896f-38d7-5d50-9e66-652a2c9cc88e', 'f162e20a-72c7-544c-b8dc-77abfd74956a', null, 'esponja', 'Esponja', null, null, 1, 1, 45, 46),
      ('044676dd-9082-5c72-9b85-1a3d729da597', 'f162e20a-72c7-544c-b8dc-77abfd74956a', null, 'massa', 'Massa do Panetone', null, null, 1, 2, 45, 46),
      ('d12c1d48-2962-5223-95e4-6b0e0cb64bcb', 'f162e20a-72c7-544c-b8dc-77abfd74956a', null, 'recheio', 'Recheio de Maracujá', null, null, 1, 3, 47, 48),
      ('b674fa10-bc17-58c0-9284-1d364e47003d', 'f162e20a-72c7-544c-b8dc-77abfd74956a', null, 'montagem', 'Montagem — Panetone Trufado de Maracujá', null, null, 1, 4, 47, 48)
    on conflict (id) do nothing;
    insert into public.recipe_ingredients (id, recipe_id, component_id, ingredient_id, position, quantity, quantity_max, unit, quantity_text, display_name, preparation, household_note, scaling, is_optional, original_text, source_page, needs_review) values
      ('bf6cb60f-4029-58d6-997b-710452f47b85', 'f162e20a-72c7-544c-b8dc-77abfd74956a', 'fceb896f-38d7-5d50-9e66-652a2c9cc88e', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 200, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '200g de farinha de trigo', 45, false),
      ('3ffa7724-d2f9-5c80-845c-a1609adbfb70', 'f162e20a-72c7-544c-b8dc-77abfd74956a', 'fceb896f-38d7-5d50-9e66-652a2c9cc88e', 'd56ba7aa-56ee-5929-b4b9-2191ceb67e9a', 2, 20, null, 'g', null, 'fermento biológico seco', null, null, 'linear', false, '20g de fermento biológico seco', 45, false),
      ('8845a5d2-5a80-55b6-897e-37f42c931634', 'f162e20a-72c7-544c-b8dc-77abfd74956a', 'fceb896f-38d7-5d50-9e66-652a2c9cc88e', '0a718c08-62f3-5af3-8577-980614b5cf9d', 3, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 45, false),
      ('997c7637-fc62-51d1-988e-76024a91156d', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', '135274a3-0f44-5575-8124-d73d9da305e9', 1, 800, null, 'g', null, 'farinha de trigo', null, null, 'linear', false, '800g de farinha de trigo', 45, false),
      ('5af0bc87-d714-5713-b7cb-86a09a006090', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', 'f2b0542e-4276-5937-aa27-615636db24fe', 2, 150, null, 'g', null, 'açúcar refinado', null, null, 'linear', false, '150g de açúcar refinado', 45, false),
      ('87ff7d0d-b106-5cc5-9b20-05b83e736807', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', null, 3, 5, null, 'colheres (sopa)', null, 'Leite em pó', null, null, 'linear', false, '5 colheres (sopa) de Leite em pó', 45, false),
      ('22db0e4b-6abb-5b89-a1d9-dca1b1f21d60', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', 'b4f34561-8417-5374-b624-7e5bba20ed3f', 4, null, null, null, '1 pitadinha', 'sal', null, null, 'linear', false, '1 pitadinha de sal', 45, false),
      ('7d49f43c-662f-58d9-824c-cfac342133f8', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', 'eadfe0cd-1a05-55b2-9d9c-fef99adbdf0a', 5, 10, null, 'unidades', null, 'gemas', null, null, 'linear', false, '10 gemas', 45, false),
      ('e5252fee-2d12-5881-a1af-892200031df2', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', '0a718c08-62f3-5af3-8577-980614b5cf9d', 6, 200, null, 'ml', null, 'água morna', null, null, 'linear', false, '200ml de água morna', 45, false),
      ('dc2a00b3-5acc-565f-99b1-57d32dff7e36', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', '1d9872a2-e69a-5cd8-b823-6e0b1e44be2b', 7, 3, null, 'colheres (sopa)', null, 'essência de baunilha', null, null, 'linear', false, '3 colheres (sopa) de essência de baunilha', 45, false),
      ('4d821a1e-2972-53b6-81d4-c0141589ab4c', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', '8566bb0d-ee09-5d4a-a651-70a1621c1264', 8, 15, null, 'ml', null, 'essência de Panetone', null, null, 'linear', false, '15ml de essência de Panetone', 45, false),
      ('5ca73d7c-af71-52e7-bad5-3bfa99b95124', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', 'ab8fb758-861c-5312-ae98-f38d81f25e6e', 9, 2, null, 'unidades', null, 'raspas de limão', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 45, false),
      ('07b5fc9c-3f57-5fc1-a0f1-6f31d1609194', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', '719de073-c900-5def-808b-af472a1c4be8', 10, 2, null, 'unidades', null, 'raspas de laranja', null, null, 'linear', false, 'Raspas de 2 limões + 2 laranjas', 45, false),
      ('7e918463-a3a6-5fe5-86f3-95903221ccee', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', null, 11, 160, null, 'g', null, 'margarina ou manteiga sem sal', null, null, 'linear', false, '160g de margarina ou manteiga (sem sal)', 45, false),
      ('3037d026-417f-5ad5-ac5c-ff22a0708980', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', '9cf7d3c9-36d9-5e20-9c00-6151636b0ac1', 12, 200, null, 'g', null, 'uvas passas', null, null, 'linear', false, '200g de uvas passas', 45, false),
      ('74414d16-dc92-50dd-a762-88aa4eec6d0e', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', '523013e5-3b5c-503c-8e3b-0efe15fa5dda', 13, 250, null, 'g', null, 'frutas cristalizadas', null, null, 'linear', false, '250g de frutas cristalizadas', 45, false),
      ('2c8ba84a-05c7-5124-8ff9-0517061b1c41', 'f162e20a-72c7-544c-b8dc-77abfd74956a', 'd12c1d48-2962-5223-95e4-6b0e0cb64bcb', '226cf1a2-0b7c-5117-8b13-4aad315d34a0', 1, 300, null, 'g', null, 'chocolate branco nobre', null, null, 'linear', false, '300g de chocolate branco nobre (não usar cobertura ou fracionado)', 47, false),
      ('bc9a5d04-b9f4-53e3-9c4b-0bfd13fbccb6', 'f162e20a-72c7-544c-b8dc-77abfd74956a', 'd12c1d48-2962-5223-95e4-6b0e0cb64bcb', '8758d73e-4fcf-508e-940d-635708436a41', 2, 80, null, 'ml', null, 'creme de leite', null, null, 'linear', false, '80ml de creme de leite', 47, false),
      ('c76dc5fe-7654-522e-91d3-549165906dcc', 'f162e20a-72c7-544c-b8dc-77abfd74956a', 'd12c1d48-2962-5223-95e4-6b0e0cb64bcb', null, 3, 50, null, 'ml', null, 'suco concentrado de maracujá', null, null, 'linear', false, '50ml de suco concentrado de maracujá', 47, false)
    on conflict (id) do nothing;
    insert into public.recipe_steps (id, recipe_id, component_id, position, instruction, original_text, tip, source_page, needs_review) values
      ('30c728a3-2de2-5356-a3f8-b53271a35442', 'f162e20a-72c7-544c-b8dc-77abfd74956a', 'fceb896f-38d7-5d50-9e66-652a2c9cc88e', 1, 'Misture a farinha, o fermento e a água morna até formar uma massa grossa e pegajosa; adicione mais água morna se necessário.', 'Misture muito bem os 3 ingredientes, (farinha, fermento e a água morna), até formar uma massa grossa e pegajosa. Adicione mais água morna caso seja necessário para ficar bem pegajosa.', null, 46, false),
      ('46914d9e-91ca-550d-9a46-b73dd53f04c0', 'f162e20a-72c7-544c-b8dc-77abfd74956a', 'fceb896f-38d7-5d50-9e66-652a2c9cc88e', 2, 'Cubra e deixe descansar por 30 a 40 minutos em local abafado e seco.', 'Cubra bem e deixe descansando por 30 a 40 minutos em local abafado e seco.', null, 46, false),
      ('0b17bb33-6a5a-563c-af13-b426ef055130', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', 1, 'Coloque a água morna em uma vasilha e acrescente as essências de baunilha e de Panetone.', 'Numa vasilha, coloque a água morna e acrescente as essências de baunilha e de Panetone.', null, 46, false),
      ('73c25e0f-abe4-5907-97cb-490f5af69085', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', 2, 'Em outra tigela, misture a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja descansada até formar uma farofa. Despeje na mistura líquida e sove por cerca de 10 minutos.', 'Em uma outra tigela, adicione a farinha, o açúcar, o sal, o leite em pó, as gemas e a esponja preparada antes e já descansada, até formar uma certa “farofa”. Em seguida despeje a ‘’farofa’’ na mistura líquida de água com as essências e sove por uns 10 minutos.', null, 46, false),
      ('0ddabf4a-1174-5266-b00c-69ddd8c6db4d', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', 3, 'Acrescente a margarina e sove até atingir o ponto de véu, esticando uma pequena porção até ficar transparente sem rasgar.', 'Acrescente a margarina e sove até chegar no ponto de véu, (pegue uma pequena porção da massa com as mãos untadas com óleo e estique com cuidado, a massa deve abrir até ficar transparente, não pode rasgar).', null, 46, false),
      ('92e66d71-375d-57dc-ab81-9887e491ae9d', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', 4, 'Adicione as raspas de limão e laranja e misture até incorporar.', 'Depois adicione as raspas de limão e laranja e mexa bem até incorporar totalmente. A massa é macia e pegajosa, e suas mãos precisam do óleo para mexer.', null, 46, false),
      ('740f0219-884b-5ace-8d43-6129c9f40071', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', 5, 'Abra a massa em superfície untada com óleo e espalhe as frutas cristalizadas e as uvas passas; enrole e modele formando uma bola.', 'Agora coloque essa massa em uma superfície untada com óleo e abra com as mãos espalhando as frutas cristalizadas e as uvas passas. Enrole bem e modele formando uma bola', null, 46, false),
      ('c64d9b3f-6a6d-5dd4-951e-f3250396fb73', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', 6, 'Coloque em uma tigela grande untada com óleo e deixe descansar entre 1h30 e 2h.', 'coloque em uma tigela bem grande untada com óleo. Deixe descansar entre 1h30m à 2h.', null, 47, false),
      ('7b46993a-f4b2-5ed9-9a39-9379b8128c30', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', 7, 'Volte para a superfície untada, divida em duas partes do mesmo tamanho e coloque nas formas até a metade.', 'Depois disso, volte para a superfície untada e dívida em duas partes do mesmo tamanho. A massa deve estar até na metade da forma de papel.', null, 47, false),
      ('5dd31c12-4ffe-5a7a-9328-47d744f1efa7', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', 8, 'Aguarde a massa crescer até a borda e asse em forno preaquecido a 180 graus por aproximadamente 30 minutos.', 'Aguarde a massa crescer até a borda e leve para assar no forno pré-aquecido em 180 graus por aproximadamente 30 minutos.', null, 47, false),
      ('8eb9ba50-6dc5-5354-8448-9d41257318de', 'f162e20a-72c7-544c-b8dc-77abfd74956a', '044676dd-9082-5c72-9b85-1a3d729da597', 9, 'Asse em forma de Panetone de 500g (13cm x 9,5cm).', 'Asse em forma de Panetone de 500g (13cm x 9,5cm)', null, 47, false),
      ('bd9be7db-4fc0-5c16-a8d4-a701da16b7e6', 'f162e20a-72c7-544c-b8dc-77abfd74956a', 'd12c1d48-2962-5223-95e4-6b0e0cb64bcb', 1, 'Derreta o chocolate branco no micro-ondas de 30 em 30 segundos ou em banho-maria.', 'Derreta o chocolate branco no micro-ondas de 30 em 30 segundos ou em banho-maria.', null, 47, false),
      ('a6e04512-519f-5595-b887-af9fb533eedd', 'f162e20a-72c7-544c-b8dc-77abfd74956a', 'd12c1d48-2962-5223-95e4-6b0e0cb64bcb', 2, 'Misture com os outros ingredientes até ficar homogêneo.', 'Misture com os outros ingredientes até ficar homogêneo.', null, 48, false),
      ('2b8df9f6-1a6d-55cc-a956-5fdc99d90eda', 'f162e20a-72c7-544c-b8dc-77abfd74956a', 'd12c1d48-2962-5223-95e4-6b0e0cb64bcb', 3, 'Leve ao congelador por meia hora ou deixe na geladeira por 8h antes de rechear.', 'Leve ao congelador por meia hora ou deixe na geladeira por 8h antes de rechear.', null, 48, false),
      ('98c643c2-4964-51f5-8fe6-aa48248148ef', 'f162e20a-72c7-544c-b8dc-77abfd74956a', 'b674fa10-bc17-58c0-9284-1d364e47003d', 1, 'Corte o topo do Panetone e reserve.', 'Comece cortando o topo do Panetone e reserve.', null, 47, false),
      ('c626bedd-f9f8-5b75-ae8c-718e0b23e681', 'f162e20a-72c7-544c-b8dc-77abfd74956a', 'b674fa10-bc17-58c0-9284-1d364e47003d', 2, 'Abra uma cavidade com faca e colher, deixando um dedo de parede para manter a estrutura.', 'Em seguida abra uma cavidade no Panetone com a ajuda de uma faca e uma colher, (sempre deixe um dedo de parede para o seu Panetone não perder a estrutura e quebrar).', null, 48, false),
      ('4da377db-58eb-5938-800e-7b1e610dbb74', 'f162e20a-72c7-544c-b8dc-77abfd74956a', 'b674fa10-bc17-58c0-9284-1d364e47003d', 3, 'Adicione o recheio com uma colher ou saco de confeitar.', 'Depois adicione o recheio com uma colher ou um saco de confeitar. Decore com um laço amarelo ou a gosto.', null, 48, false),
      ('dee96da0-14ee-5d83-badb-2c6e89944514', 'f162e20a-72c7-544c-b8dc-77abfd74956a', 'b674fa10-bc17-58c0-9284-1d364e47003d', 4, 'Passe um pouco do recheio nas beiradas para colar a tampa, quando indicado na receita.', 'Passe um pouquinho do recheio nas beiradinhas para “colar” a tampa.', null, 48, false),
      ('4e1a66bf-2dc6-5b8f-9e6b-930a4c8d1237', 'f162e20a-72c7-544c-b8dc-77abfd74956a', 'b674fa10-bc17-58c0-9284-1d364e47003d', 5, 'Recoloque a tampa e finalize conforme a decoração indicada na receita.', 'Por último coloque a tampa do seu Panetone/Chocotone e decore da maneira de sua preferência, usando sua criatividade.', null, 48, false)
    on conflict (id) do nothing;
    insert into public.recipe_tags (id, recipe_id, tag) values
      ('dc942999-3642-53bd-b60b-7c0a2abba15f', 'f162e20a-72c7-544c-b8dc-77abfd74956a', 'natal'),
      ('110edf5f-2fe1-5977-81eb-0963eded0203', 'f162e20a-72c7-544c-b8dc-77abfd74956a', 'panetone')
    on conflict (recipe_id, tag) do nothing;
    insert into public.review_flags (id, recipe_id, source_document_id, entity, entity_id, field, severity, message, source_page) values
      ('f8559408-1985-5eee-9eb4-7d76660a063f', 'f162e20a-72c7-544c-b8dc-77abfd74956a', null, 'recipe', 'f162e20a-72c7-544c-b8dc-77abfd74956a', 'yield', 'warning', 'A apostila informa rendimento de 5 unidades de 500g, mas também orienta dividir a massa em duas partes. Confirmar o rendimento na revisão.', 46),
      ('e7b1e082-7134-59f3-9f83-c18997070241', 'f162e20a-72c7-544c-b8dc-77abfd74956a', null, 'recipe', 'f162e20a-72c7-544c-b8dc-77abfd74956a', 'source_pages', 'warning', 'Paginação baseada na transcrição enviada; conferir no PDF original antes da publicação.', 45)
    on conflict (id) do nothing;
  end if;
end $ficha$;

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
  ('9e47ea54-4bee-52c0-a03d-4bf13bb2f0f2', null, '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'document', '00135c34-aa9a-5715-98cb-6af65cfc83f6', 'toc', 'warning', 'Títulos e páginas desta coleção: Transcrição enviada pelo autor nesta conversa; páginas apresentadas na transcrição, aguardando conferência visual do PDF original.. Nenhuma ficha foi estruturada sem o PDF.', null),
  ('d6e5185d-f45e-51cb-ac9d-3d66fa6fdf5e', null, '3a4a09a2-e60d-58ff-bc8f-3bb9217ff12b', 'document', '3a4a09a2-e60d-58ff-bc8f-3bb9217ff12b', 'toc', 'warning', 'Títulos e páginas desta coleção: Índice informado no MVP — confirmar no PDF. Nenhuma ficha foi estruturada sem o PDF.', null),
  ('9c84114a-4184-5c91-97c1-d8e289bb2187', '0d32a443-044d-5b39-bcba-98c64b01f4d5', null, 'recipe', '0d32a443-044d-5b39-bcba-98c64b01f4d5', 'source_page_start', 'info', 'Componente citado no escopo do projeto; página a confirmar no PDF.', null),
  ('0aff65f1-7a64-571a-9473-d1cc8d0b25c8', '55634b07-66b8-577d-a0f3-37e5665ac12a', null, 'recipe', '55634b07-66b8-577d-a0f3-37e5665ac12a', 'source_page_start', 'info', 'Componente citado no escopo do projeto; página a confirmar no PDF.', null),
  ('a15242ba-c0f1-5ece-bb7b-864c28cdb1bf', null, '9f1834ff-9e61-54b7-aaa5-c09bc034f1b0', 'document', '9f1834ff-9e61-54b7-aaa5-c09bc034f1b0', 'toc', 'warning', 'Títulos e páginas desta coleção: Levantamento do MVP — confirmar no PDF. Nenhuma ficha foi estruturada sem o PDF.', null),
  ('a1ef808c-5c8e-5bd2-b980-0d29084be210', null, '9f1834ff-9e61-54b7-aaa5-c09bc034f1b0', 'document', '9f1834ff-9e61-54b7-aaa5-c09bc034f1b0', 'compatibilities', 'warning', 'Combinações inferidas dos títulos do material (base doce com recheios doces; base salgada com recheios salgados). Confirmar no PDF, inclusive as finalizações, antes de liberar o montador.', null),
  ('5a6ec911-f05d-5666-acb0-1555599926a0', null, '48d7904c-48c4-5e7e-9d71-c3f89a3a0026', 'document', '48d7904c-48c4-5e7e-9d71-c3f89a3a0026', 'toc', 'warning', 'Títulos e páginas desta coleção: Índice informado no MVP — confirmar no PDF. Nenhuma ficha foi estruturada sem o PDF.', null)
on conflict (id) do nothing;

commit;
