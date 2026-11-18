import type { RecipeCompatibility } from './types';

/**
 * O montador só pode oferecer combinações confirmadas contra a fonte original.
 * Compatibilidades pendentes permanecem no banco para revisão, mas nunca viram opções.
 */
export function verifiedRabanadaCompatibilities(
  compatibilities: readonly RecipeCompatibility[],
): RecipeCompatibility[] {
  return compatibilities.filter((item) => item.verified);
}

export function pendingRabanadaCompatibilityCount(
  compatibilities: readonly RecipeCompatibility[],
): number {
  return compatibilities.filter((item) => !item.verified).length;
}

export function rabanadaBaseIds(
  compatibilities: readonly RecipeCompatibility[],
): Set<string> {
  return new Set(verifiedRabanadaCompatibilities(compatibilities).map((item) => item.recipe_id));
}

export function rabanadaOptionIds(
  compatibilities: readonly RecipeCompatibility[],
  baseId: string,
  relation: string,
): Set<string> {
  return new Set(
    verifiedRabanadaCompatibilities(compatibilities)
      .filter((item) => item.recipe_id === baseId && item.relation === relation)
      .map((item) => item.compatible_recipe_id),
  );
}
