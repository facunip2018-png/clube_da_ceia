/** Ações de escrita usadas por várias telas. Todas passam pelo DataStore (RLS no Supabase, regras equivalentes na demonstração). */
import type { Ingredient, MealPlan, RecipeDetail, ShoppingList } from '@/lib/types';
import { applyRecipeToList, linesFromRecipe, removeRecipeFromList, type ListChange } from '@/lib/shopping';
import { DEFAULT_TASKS, defaultTaskDueDate } from '@/lib/schedule';
import { AppError } from '@/lib/editorial';
import { invalidate } from './hooks';
import type { DataStore } from './store';

export async function toggleFavorite(store: DataStore, recipeId: string, isFavorite: boolean): Promise<boolean> {
  if (isFavorite) await store.remove('recipe_favorites', { recipe_id: recipeId });
  else await store.insert('recipe_favorites', { recipe_id: recipeId });
  await invalidate('recipe_favorites');
  return !isFavorite;
}

export async function ensureDefaultList(store: DataStore): Promise<ShoppingList> {
  const lists = await store.list('shopping_lists', { order: [['created_at', 'asc']], limit: 1 });
  if (lists[0]) return lists[0];
  const [created] = await store.insert('shopping_lists', { title: 'Minha lista', is_default: true });
  await invalidate('shopping_lists');
  return created;
}

async function applyListChange(store: DataStore, listId: string, change: ListChange) {
  for (const id of change.deletes) await store.remove('shopping_items', { id });
  for (const { id, patch } of change.updates) await store.update('shopping_items', { id }, patch);
  if (change.inserts.length) await store.insert('shopping_items', change.inserts.map((item) => ({ ...item, list_id: listId })));
  await invalidate('shopping_items', 'refresh_my_challenges');
}

/** Coloca (ou atualiza) os ingredientes de uma receita na lista de compras. */
export async function addRecipeToShoppingList(store: DataStore, detail: RecipeDetail, factor: number, catalog: Map<string, Ingredient>): Promise<number> {
  if (!detail.hasContent) throw new AppError('CONTENT_REQUIRED', 'Esta receita ainda não tem ficha com ingredientes.');
  const list = await ensureDefaultList(store);
  const items = await store.list('shopping_items', { eq: { list_id: list.id } });
  const lines = linesFromRecipe(detail, factor, catalog);
  await applyListChange(store, list.id, applyRecipeToList(items, lines, detail.recipe.id));
  return lines.length;
}

export async function removeRecipeFromShoppingList(store: DataStore, recipeId: string): Promise<void> {
  const lists = await store.list('shopping_lists', { order: [['created_at', 'asc']], limit: 1 });
  if (!lists[0]) return;
  const items = await store.list('shopping_items', { eq: { list_id: lists[0].id } });
  await applyListChange(store, lists[0].id, removeRecipeFromList(items, recipeId));
}

export interface NewPlanInput {
  title: string;
  occasion: MealPlan['occasion'];
  event_date: string;
  serve_time: string | null;
  guests: number;
}

/** Cria o planejamento já com o checklist padrão de organização. */
export async function createPlan(store: DataStore, input: NewPlanInput): Promise<MealPlan> {
  const [plan] = await store.insert('meal_plans', input);
  await store.insert(
    'plan_tasks',
    DEFAULT_TASKS.map((task, index) => ({
      plan_id: plan.id,
      title: task.title,
      kind: 'default' as const,
      ref_key: task.ref_key,
      due_at: defaultTaskDueDate(input.event_date, task.daysBefore),
      position: index + 1,
    })),
  );
  await invalidate('meal_plans', 'plan_tasks', 'refresh_my_challenges');
  return plan;
}

export async function addRecipeToPlan(store: DataStore, planId: string, recipeId: string, factor = 1): Promise<'added' | 'exists'> {
  const existing = await store.list('plan_recipes', { eq: { plan_id: planId, recipe_id: recipeId } });
  if (existing.length) return 'exists';
  const all = await store.list('plan_recipes', { eq: { plan_id: planId } });
  await store.insert('plan_recipes', { plan_id: planId, recipe_id: recipeId, factor, position: all.length + 1 });
  await invalidate('plan_recipes', 'refresh_my_challenges');
  return 'added';
}

export async function finishCookingSession(store: DataStore, sessionId: string, completedSteps: number[]): Promise<void> {
  await store.update('cooking_sessions', { id: sessionId }, { status: 'finished', finished_at: new Date().toISOString(), completed_steps: completedSteps });
  await store.rpc('refresh_my_challenges').catch(() => undefined);
  await invalidate('cooking_sessions', 'refresh_my_challenges', 'user_challenges');
}
