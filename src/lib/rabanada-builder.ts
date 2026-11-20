import type { Recipe, RecipeComponent, RecipeCompatibility } from './types';

export interface LinkedRabanadaPreparation {
  component: RecipeComponent;
  recipe: Recipe;
}

const isPublishedStructured = (recipe: Recipe) =>
  recipe.status === 'published' && recipe.content_state === 'structured';

const bySourcePage = (a: Recipe, b: Recipe) =>
  (a.source_page_start ?? Number.MAX_SAFE_INTEGER) - (b.source_page_start ?? Number.MAX_SAFE_INTEGER)
  || a.position - b.position;

/** Bases disponíveis somente quando possuem ao menos uma combinação documentalmente verificada. */
export function getVerifiedRabanadaBases(
  recipes: Recipe[],
  compatibilities: RecipeCompatibility[],
): Recipe[] {
  const baseIds = new Set(
    compatibilities
      .filter((row) => row.verified && row.relation === 'recheio')
      .map((row) => row.recipe_id),
  );

  return recipes
    .filter((recipe) =>
      baseIds.has(recipe.id)
      && recipe.kind === 'component'
      && recipe.component_role === 'base'
      && isPublishedStructured(recipe),
    )
    .sort(bySourcePage);
}

/** Recheios/variações liberados para uma base específica, sem inferência por nome ou sabor. */
export function getVerifiedRabanadaFillings(
  baseId: string,
  recipes: Recipe[],
  compatibilities: RecipeCompatibility[],
): Recipe[] {
  const fillingIds = new Set(
    compatibilities
      .filter((row) => row.verified && row.recipe_id === baseId && row.relation === 'recheio')
      .map((row) => row.compatible_recipe_id),
  );

  return recipes
    .filter((recipe) =>
      fillingIds.has(recipe.id)
      && recipe.kind === 'variation'
      && isPublishedStructured(recipe),
    )
    .sort(bySourcePage);
}

/** Preparos exibidos vêm exclusivamente dos componentes vinculados à variação escolhida. */
export function getRabanadaPreparations(
  variationId: string,
  recipes: Recipe[],
  componentLinks: RecipeComponent[],
): LinkedRabanadaPreparation[] {
  const recipesById = new Map(recipes.map((recipe) => [recipe.id, recipe]));

  return componentLinks
    .filter((component) => component.recipe_id === variationId && component.linked_recipe_id !== null)
    .sort((a, b) => a.position - b.position)
    .flatMap((component) => {
      const linkedRecipe = component.linked_recipe_id ? recipesById.get(component.linked_recipe_id) : undefined;
      if (!linkedRecipe || linkedRecipe.kind !== 'component' || !isPublishedStructured(linkedRecipe)) return [];
      return [{ component, recipe: linkedRecipe }];
    });
}
