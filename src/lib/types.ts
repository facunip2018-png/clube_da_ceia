/**
 * Tipos das tabelas do banco (espelham supabase/migrations/…_schema.sql).
 * Valores numeric chegam como number pela API do Supabase.
 */
export type RecipeStatus = 'draft' | 'review' | 'approved' | 'published' | 'pending_permission' | 'archived';
export type RecipeKind = 'recipe' | 'component' | 'variation';
export type ComponentRole = 'base' | 'massa' | 'esponja' | 'recheio' | 'cobertura' | 'calda' | 'creme' | 'montagem' | 'finalizacao' | 'fritura' | 'outro';
export type Scaling = 'linear' | 'manual' | 'fixed';
export type Severity = 'info' | 'warning' | 'blocker';

interface Timestamps {
  created_at: string;
  updated_at?: string;
}

export interface Season extends Timestamps {
  id: string;
  slug: string;
  name: string;
  description: string | null;
  status: 'draft' | 'active' | 'archived';
  price_cents: number | null;
  currency: string;
  sales_starts_at: string | null;
  sales_ends_at: string | null;
  access_starts_at: string | null;
  access_ends_at: string | null;
  admin_notice: string | null;
}

export interface Profile extends Timestamps {
  id: string;
  email: string | null;
  full_name: string;
  avatar_url: string | null;
  role: 'customer' | 'admin';
  preferences: Record<string, unknown>;
}

export interface Collection extends Timestamps {
  id: string;
  slug: string;
  name: string;
  description: string | null;
  cover_image: string | null;
  experience: 'catalog' | 'builder';
  position: number;
  is_visible: boolean;
  admin_notice: string | null;
}

export interface SourceDocument extends Timestamps {
  id: string;
  slug: string;
  collection_id: string | null;
  title: string;
  author: string | null;
  publisher: string | null;
  file_name: string | null;
  language: string;
  page_count: number | null;
  file_status: 'not_provided' | 'awaiting_upload' | 'received' | 'stored';
  storage_path: string | null;
  sha256: string | null;
  commercial_permission: 'unknown' | 'confirmed' | 'restricted' | 'denied';
  permission_notes: string | null;
  permission_confirmed_by: string | null;
  permission_confirmed_at: string | null;
  measurement_notes: string | null;
  import_notes: string | null;
  toc: { title: string; printed_page?: number; pdf_page?: number }[];
}

/** Visão pública mínima do documento (view source_document_refs). */
export interface SourceDocumentRef {
  id: string;
  title: string;
  author: string | null;
  publisher: string | null;
  language: string;
}

export interface SupportMaterial extends Timestamps {
  id: string;
  slug: string;
  kind: 'utensilios' | 'ingredientes' | 'dicas' | 'orientacoes';
  title: string;
  body: string;
  source_document_id: string | null;
  source_page: number | null;
  position: number;
  is_visible: boolean;
}

export interface Recipe extends Timestamps {
  id: string;
  slug: string;
  collection_id: string;
  source_document_id: string | null;
  kind: RecipeKind;
  component_role: ComponentRole | null;
  flavor: 'doce' | 'salgado' | null;
  title: string;
  original_title: string | null;
  original_language: string;
  translation_status: 'not_needed' | 'pending' | 'in_review' | 'reviewed';
  description: string | null;
  cover_image: string | null;
  difficulty: 'facil' | 'media' | 'dificil' | null;
  yield_quantity: number | null;
  yield_unit: string | null;
  yield_unit_plural: string | null;
  yield_detail: string | null;
  yield_text: string | null;
  servings: number | null;
  prep_minutes: number | null;
  cook_minutes: number | null;
  bake_minutes: number | null;
  chill_minutes: number | null;
  rest_minutes: number | null;
  chill_is_minimum: boolean;
  measure_note: string | null;
  source_page_start: number | null;
  source_page_end: number | null;
  source_pages_extra: number[];
  page_ref_verified: boolean;
  content_state: 'catalogued' | 'structured';
  status: RecipeStatus;
  position: number;
  is_featured: boolean;
  reviewed_by: string | null;
  reviewed_at: string | null;
  published_at: string | null;
}

export interface RecipeComponent extends Timestamps {
  id: string;
  recipe_id: string;
  linked_recipe_id: string | null;
  role: ComponentRole;
  title: string;
  original_title: string | null;
  description: string | null;
  multiplier: number;
  position: number;
  source_page_start: number | null;
  source_page_end: number | null;
}

export interface Ingredient extends Timestamps {
  id: string;
  slug: string;
  name: string;
  category: string;
  is_shoppable: boolean;
}

export interface RecipeIngredient extends Timestamps {
  id: string;
  recipe_id: string;
  component_id: string | null;
  ingredient_id: string | null;
  position: number;
  quantity: number | null;
  quantity_max: number | null;
  unit: string | null;
  quantity_text: string | null;
  display_name: string;
  preparation: string | null;
  household_note: string | null;
  scaling: Scaling;
  is_optional: boolean;
  original_text: string | null;
  source_page: number | null;
  needs_review: boolean;
}

export interface RecipeStep extends Timestamps {
  id: string;
  recipe_id: string;
  component_id: string | null;
  position: number;
  instruction: string;
  original_text: string | null;
  tip: string | null;
  source_page: number | null;
  needs_review: boolean;
}

export interface RecipeStepIngredient {
  id: string;
  recipe_id: string;
  step_id: string;
  recipe_ingredient_id: string | null;
  component_id: string | null;
  position: number;
  created_at: string;
}

export interface RecipeStepTimer extends Timestamps {
  id: string;
  recipe_id: string;
  step_id: string;
  label: string;
  duration_seconds: number;
  kind: 'cook' | 'bake' | 'chill' | 'rest' | 'other';
  is_minimum: boolean;
  temperature_c: number | null;
  original_text: string | null;
  needs_review: boolean;
  position: number;
}

export interface RecipeNote extends Timestamps {
  id: string;
  recipe_id: string;
  kind: 'tip' | 'note' | 'equipment';
  title: string | null;
  body: string;
  original_text: string | null;
  source_page: number | null;
  position: number;
}

export interface RecipeTag {
  id: string;
  recipe_id: string;
  tag: string;
  created_at: string;
}

export interface RecipeCompatibility {
  id: string;
  recipe_id: string;
  compatible_recipe_id: string;
  relation: string;
  source_page: number | null;
  verified: boolean;
  note: string | null;
  created_at: string;
}

export interface ReviewFlag {
  id: string;
  recipe_id: string | null;
  source_document_id: string | null;
  entity: 'recipe' | 'component' | 'ingredient' | 'step' | 'timer' | 'note' | 'document';
  entity_id: string | null;
  field: string | null;
  severity: Severity;
  message: string;
  source_page: number | null;
  resolved_at: string | null;
  resolved_by: string | null;
  resolution_note: string | null;
  created_at: string;
}

export interface RecipeFavorite {
  id: string;
  user_id: string;
  recipe_id: string;
  created_at: string;
}

export interface MealPlan extends Timestamps {
  id: string;
  user_id: string;
  season_id: string | null;
  occasion: 'natal' | 'ano_novo' | 'outro';
  title: string;
  event_date: string | null;
  serve_time: string | null;
  guests: number;
  notes: string | null;
  default_block_minutes: number;
  status: 'active' | 'done' | 'archived';
}

export interface PlanRecipe extends Timestamps {
  id: string;
  plan_id: string;
  user_id: string;
  recipe_id: string;
  factor: number;
  position: number;
  notes: string | null;
  builder_selection: Record<string, unknown> | null;
}

export interface PlanTask extends Timestamps {
  id: string;
  plan_id: string;
  user_id: string;
  title: string;
  kind: 'default' | 'schedule' | 'custom';
  ref_key: string | null;
  due_at: string | null;
  is_done: boolean;
  done_at: string | null;
  position: number;
}

export interface ShoppingList extends Timestamps {
  id: string;
  user_id: string;
  plan_id: string | null;
  title: string;
  is_default: boolean;
}

export interface ShoppingSource {
  recipe_id: string;
  recipe_title: string;
  quantity: number | null;
  unit: string | null;
  factor: number;
}

export interface ShoppingItem extends Timestamps {
  id: string;
  list_id: string;
  user_id: string;
  ingredient_id: string | null;
  name: string;
  category: string;
  quantity: number | null;
  unit: string | null;
  quantity_text: string | null;
  is_checked: boolean;
  checked_at: string | null;
  is_manual: boolean;
  quantity_edited: boolean;
  sources: ShoppingSource[];
  note: string | null;
  position: number;
}

export interface CookingSession extends Timestamps {
  id: string;
  user_id: string;
  recipe_id: string;
  plan_id: string | null;
  factor: number;
  current_step: number;
  completed_steps: number[];
  status: 'active' | 'finished' | 'abandoned';
  started_at: string;
  finished_at: string | null;
}

export type ChallengeRule = 'cook_any' | 'cook_in_collection' | 'create_plan' | 'complete_plan' | 'shopping_done' | 'favorites' | 'chef_chat' | 'manual';

export interface Challenge extends Timestamps {
  id: string;
  slug: string;
  season_id: string | null;
  title: string;
  description: string | null;
  icon: string | null;
  points: number;
  badge_name: string | null;
  badge_tier: 'bronze' | 'prata' | 'ouro' | null;
  rule_type: ChallengeRule;
  rule_config: { target?: number; collection_slug?: string; min_items?: number };
  allows_photo: boolean;
  is_active: boolean;
  position: number;
}

export interface UserChallenge extends Timestamps {
  id: string;
  user_id: string;
  challenge_id: string;
  progress: number;
  target: number;
  completed_at: string | null;
  points_awarded: number;
}

export interface ChallengeSubmission extends Timestamps {
  id: string;
  user_id: string;
  challenge_id: string;
  photo_path: string | null;
  note: string | null;
  status: 'submitted' | 'approved' | 'rejected';
  reviewed_by: string | null;
  reviewed_at: string | null;
}

export interface AiConversation extends Timestamps {
  id: string;
  user_id: string;
  title: string | null;
  recipe_id: string | null;
  archived_at: string | null;
}

export interface AiMessage {
  id: string;
  conversation_id: string;
  user_id: string;
  role: 'user' | 'assistant';
  content: string;
  grounded_recipe_ids: string[];
  model: string | null;
  tokens_in: number | null;
  tokens_out: number | null;
  created_at: string;
}

export interface Order extends Timestamps {
  id: string;
  user_id: string;
  season_id: string;
  status: 'pending' | 'approved' | 'rejected' | 'cancelled' | 'refunded' | 'charged_back' | 'in_mediation' | 'review_required';
  amount_cents: number;
  currency: string;
  provider: string;
  provider_preference_id: string | null;
  provider_payment_id: string | null;
  paid_at: string | null;
}

export interface PaymentTransaction {
  id: string;
  order_id: string;
  provider: string;
  provider_payment_id: string;
  status: string;
  status_detail: string | null;
  amount_cents: number | null;
  currency: string | null;
  seen_count: number;
  last_seen_at: string;
  created_at: string;
}

export interface Membership extends Timestamps {
  id: string;
  user_id: string;
  season_id: string;
  status: 'active' | 'revoked';
  source: 'purchase' | 'courtesy' | 'admin';
  order_id: string | null;
  granted_by: string | null;
  granted_at: string;
  revoked_at: string | null;
  revoke_reason: string | null;
  admin_locked: boolean;
  expires_at: string | null;
}

export interface AuditLog {
  id: string;
  actor_id: string | null;
  actor_email: string | null;
  action: string;
  entity: string;
  entity_id: string | null;
  summary: string | null;
  old_data: Record<string, unknown> | null;
  new_data: Record<string, unknown> | null;
  created_at: string;
}

export interface CatalogStat {
  collection_id: string;
  published_recipes: number;
  published_components: number;
  published_variations: number;
  in_preparation: number;
}

export interface Access {
  authenticated: boolean;
  is_admin: boolean;
  has_access: boolean;
  season_id?: string | null;
  season_name?: string | null;
  access_until?: string | null;
  source?: string | null;
}

/** Mapa tabela → tipo de linha, usado pela camada de dados. */
export interface Tables {
  seasons: Season;
  profiles: Profile;
  collections: Collection;
  source_documents: SourceDocument;
  source_document_refs: SourceDocumentRef;
  support_materials: SupportMaterial;
  recipes: Recipe;
  recipe_components: RecipeComponent;
  ingredients: Ingredient;
  recipe_ingredients: RecipeIngredient;
  recipe_steps: RecipeStep;
  recipe_step_ingredients: RecipeStepIngredient;
  recipe_step_timers: RecipeStepTimer;
  recipe_notes: RecipeNote;
  recipe_tags: RecipeTag;
  recipe_compatibilities: RecipeCompatibility;
  review_flags: ReviewFlag;
  recipe_favorites: RecipeFavorite;
  meal_plans: MealPlan;
  plan_recipes: PlanRecipe;
  plan_tasks: PlanTask;
  shopping_lists: ShoppingList;
  shopping_items: ShoppingItem;
  cooking_sessions: CookingSession;
  challenges: Challenge;
  user_challenges: UserChallenge;
  challenge_submissions: ChallengeSubmission;
  ai_conversations: AiConversation;
  ai_messages: AiMessage;
  orders: Order;
  payment_transactions: PaymentTransaction;
  memberships: Membership;
  admin_audit_logs: AuditLog;
}
export type TableName = keyof Tables;

/** Ficha completa de uma receita, já organizada por partes. */
export interface RecipePart {
  component: RecipeComponent;
  ingredients: RecipeIngredient[];
  steps: (RecipeStep & { timers: RecipeStepTimer[]; uses: StepUse[] })[];
}
export type StepUse =
  | { type: 'ingredient'; ingredient: RecipeIngredient }
  | { type: 'component'; component: RecipeComponent };

export interface RecipeDetail {
  recipe: Recipe;
  collection: Collection | null;
  source: SourceDocumentRef | null;
  parts: RecipePart[];
  tips: RecipeNote[];
  notes: RecipeNote[];
  equipment: RecipeNote[];
  tags: string[];
  /** false quando a pessoa não tem acesso às partes premium (ou a ficha ainda não existe) */
  hasContent: boolean;
}
