import type { Recipe, RecipeComponent } from '@/lib/types';

const COMMON_PREPARATION_ROLES = new Set(['calda', 'fritura']);

/**
 * Retorna somente as massas que são efetivamente usadas por uma variação.
 * Os antigos registros de orientação do pão também tinham component_role=base,
 * mas nenhuma variação os referencia em recipe_components.
 */
export function getRabanadaBaseRecipes(
  recipes: Recipe[],
  components: RecipeComponent[],
): Recipe[] {
  const linkedBaseIds = new Set(
    components
      .filter((component) => {
        if (component.role !== 'base' || !component.linked_recipe_id) return false;
        return recipes.some((recipe) => recipe.id === component.recipe_id && recipe.kind === 'variation');
      })
      .map((component) => component.linked_recipe_id as string),
  );

  return recipes.filter(
    (recipe) =>
      recipe.kind === 'component' &&
      recipe.component_role === 'base' &&
      linkedBaseIds.has(recipe.id),
  );
}

/** Variações cuja própria composição aponta para a massa selecionada. */
export function getRabanadaVariationsForBase(
  baseId: string,
  recipes: Recipe[],
  components: RecipeComponent[],
): Recipe[] {
  const variationIds = new Set(
    components
      .filter((component) => component.role === 'base' && component.linked_recipe_id === baseId)
      .map((component) => component.recipe_id),
  );

  return recipes.filter((recipe) => recipe.kind === 'variation' && variationIds.has(recipe.id));
}

/**
 * Preparos compartilhados por todas as variações da massa selecionada.
 * Só considera calda e fritura ligadas a fichas próprias; recheios e
 * finalizações específicos permanecem dentro da composição de cada variação.
 */
export function getRabanadaCommonPreparations(
  baseId: string,
  recipes: Recipe[],
  components: RecipeComponent[],
): Recipe[] {
  const variations = getRabanadaVariationsForBase(baseId, recipes, components);
  if (!variations.length) return [];

  const firstVariation = variations[0];
  const firstLinks = components
    .filter(
      (component) =>
        component.recipe_id === firstVariation.id &&
        COMMON_PREPARATION_ROLES.has(component.role) &&
        component.linked_recipe_id,
    )
    .sort((a, b) => a.position - b.position);

  const commonIds = new Set(firstLinks.map((component) => component.linked_recipe_id as string));

  for (const variation of variations.slice(1)) {
    const linkedIds = new Set(
      components
        .filter(
          (component) =>
            component.recipe_id === variation.id &&
            COMMON_PREPARATION_ROLES.has(component.role) &&
            component.linked_recipe_id,
        )
        .map((component) => component.linked_recipe_id as string),
    );

    for (const id of commonIds) {
      if (!linkedIds.has(id)) commonIds.delete(id);
    }
  }

  const seen = new Set<string>();
  return firstLinks.flatMap((component) => {
    const id = component.linked_recipe_id;
    if (!id || !commonIds.has(id) || seen.has(id)) return [];
    seen.add(id);
    const linkedRecipe = recipes.find((recipe) => recipe.id === id);
    return linkedRecipe ? [linkedRecipe] : [];
  });
}

/** Composição completa em ordem de origem, incluindo partes sem ficha vinculada. */
export function getRabanadaComposition(
  recipeId: string,
  recipes: Recipe[],
  components: RecipeComponent[],
): { component: RecipeComponent; linkedRecipe: Recipe | null }[] {
  return components
    .filter((component) => component.recipe_id === recipeId)
    .sort((a, b) => a.position - b.position)
    .map((component) => ({
      component,
      linkedRecipe: component.linked_recipe_id
        ? recipes.find((recipe) => recipe.id === component.linked_recipe_id) ?? null
        : null,
    }));
}
