/** Monta a ficha completa (partes → ingredientes → etapas → temporizadores) a partir das linhas do banco. */
import type {
  Collection, Recipe, RecipeComponent, RecipeDetail, RecipeIngredient, RecipeNote, RecipePart, RecipeStep,
  RecipeStepIngredient, RecipeStepTimer, RecipeTag, SourceDocumentRef, StepUse,
} from './types';

export interface RecipeRows {
  components: RecipeComponent[];
  ingredients: RecipeIngredient[];
  steps: RecipeStep[];
  stepIngredients: RecipeStepIngredient[];
  timers: RecipeStepTimer[];
  notes: RecipeNote[];
  tags: RecipeTag[];
}

const byPosition = <T extends { position: number }>(a: T, b: T) => a.position - b.position;

export function assembleRecipeDetail(
  recipe: Recipe,
  rows: RecipeRows,
  extra: { collection?: Collection | null; source?: SourceDocumentRef | null } = {},
): RecipeDetail {
  const ownComponents = rows.components.filter((c) => c.recipe_id === recipe.id).sort(byPosition);
  const ingredientById = new Map(rows.ingredients.map((i) => [i.id, i]));
  const componentById = new Map(rows.components.map((c) => [c.id, c]));

  const parts: RecipePart[] = ownComponents.map((component) => {
    // Parte compartilhada: usa ingredientes e etapas do componente vinculado, na proporção indicada.
    const sourceRecipeId = component.linked_recipe_id ?? recipe.id;
    const linked = Boolean(component.linked_recipe_id);
    const ingredients = rows.ingredients
      .filter((i) => (linked ? i.recipe_id === sourceRecipeId : i.component_id === component.id))
      .sort(byPosition)
      .map((i) => (linked && component.multiplier !== 1 && i.quantity != null && i.scaling !== 'fixed'
        ? { ...i, quantity: i.quantity * component.multiplier, quantity_max: i.quantity_max != null ? i.quantity_max * component.multiplier : null }
        : i));
    const steps = rows.steps
      .filter((s) => (linked ? s.recipe_id === sourceRecipeId : s.component_id === component.id))
      .sort(byPosition)
      .map((step) => ({
        ...step,
        timers: rows.timers.filter((t) => t.step_id === step.id).sort(byPosition),
        uses: rows.stepIngredients
          .filter((u) => u.step_id === step.id)
          .sort(byPosition)
          .map((u): StepUse | null => {
            if (u.recipe_ingredient_id) {
              const ingredient = ingredientById.get(u.recipe_ingredient_id);
              return ingredient ? { type: 'ingredient', ingredient } : null;
            }
            const used = u.component_id ? componentById.get(u.component_id) : null;
            return used ? { type: 'component', component: used } : null;
          })
          .filter((u): u is StepUse => u !== null),
      }));
    return { component, ingredients, steps };
  });

  const notes = rows.notes.filter((n) => n.recipe_id === recipe.id).sort(byPosition);
  return {
    recipe,
    collection: extra.collection ?? null,
    source: extra.source ?? null,
    parts,
    tips: notes.filter((n) => n.kind === 'tip'),
    notes: notes.filter((n) => n.kind === 'note'),
    equipment: notes.filter((n) => n.kind === 'equipment'),
    tags: rows.tags.filter((t) => t.recipe_id === recipe.id).map((t) => t.tag),
    hasContent: parts.some((p) => p.steps.length > 0 || p.ingredients.length > 0),
  };
}

export interface FlatStep {
  index: number;
  total: number;
  part: RecipePart;
  partIndex: number;
  stepInPart: number;
  step: RecipePart['steps'][number];
}

/** Sequência linear de etapas para o modo cozinheiro. */
export function flattenSteps(detail: RecipeDetail): FlatStep[] {
  const flat: Omit<FlatStep, 'total' | 'index'>[] = [];
  detail.parts.forEach((part, partIndex) => {
    part.steps.forEach((step, stepInPart) => flat.push({ part, partIndex, stepInPart, step }));
  });
  return flat.map((item, index) => ({ ...item, index, total: flat.length }));
}

/** Tempos informados pela ficha (nunca estimados). */
export function knownTimes(recipe: Recipe): { label: string; minutes: number; minimum: boolean }[] {
  const entries: [string, number | null, boolean][] = [
    ['Preparo', recipe.prep_minutes, false],
    ['Fogo', recipe.cook_minutes, false],
    ['Forno', recipe.bake_minutes, false],
    ['Geladeira', recipe.chill_minutes, recipe.chill_is_minimum],
    ['Descanso', recipe.rest_minutes, false],
  ];
  return entries.filter(([, m]) => m != null && m > 0).map(([label, minutes, minimum]) => ({ label, minutes: minutes as number, minimum }));
}

export const ROLE_LABELS: Record<string, string> = {
  base: 'Base', massa: 'Massa', esponja: 'Esponja', recheio: 'Recheio', cobertura: 'Cobertura', calda: 'Calda',
  creme: 'Creme', montagem: 'Montagem', finalizacao: 'Finalização', fritura: 'Fritura', outro: 'Preparo',
};

export const STATUS_LABELS: Record<Recipe['status'], string> = {
  draft: 'Rascunho', review: 'Em revisão', approved: 'Aprovada', published: 'Publicada',
  pending_permission: 'Aguardando permissão', archived: 'Arquivada',
};

export const DIFFICULTY_LABELS: Record<string, string> = { facil: 'Fácil', media: 'Média', dificil: 'Difícil' };
