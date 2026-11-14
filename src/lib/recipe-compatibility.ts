import type { RecipeCompatibility } from './types';

/**
 * Clientes só recebem combinações conferidas no material de origem.
 * A administração pode visualizar as pendências na prévia de curadoria.
 */
export function visibleRecipeCompatibilities(
  compatibilities: readonly RecipeCompatibility[],
  isAdmin: boolean,
): RecipeCompatibility[] {
  return isAdmin
    ? [...compatibilities]
    : compatibilities.filter((compatibility) => compatibility.verified);
}
