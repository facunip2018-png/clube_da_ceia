import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { Ingredient, Recipe, RecipeDetail, Tables } from '@/lib/types';
import { assembleRecipeDetail } from '@/lib/recipe-view';

type Demo = { tables: { [K in keyof Tables]?: Tables[K][] } };

export const demo: Demo = JSON.parse(readFileSync(join(__dirname, '..', '..', 'src', 'server', 'demo-data.generated.json'), 'utf8'));
const t = <K extends keyof Tables>(name: K): Tables[K][] => (demo.tables[name] ?? []) as Tables[K][];

export function detailOf(slug: string): RecipeDetail {
  const recipe = t('recipes').find((r) => r.slug === slug) as Recipe;
  return assembleRecipeDetail(
    recipe,
    {
      components: t('recipe_components'),
      ingredients: t('recipe_ingredients'),
      steps: t('recipe_steps'),
      stepIngredients: t('recipe_step_ingredients'),
      timers: t('recipe_step_timers'),
      notes: t('recipe_notes'),
      tags: t('recipe_tags'),
    },
    { collection: t('collections').find((c) => c.id === recipe.collection_id) ?? null },
  );
}

export const pave = () => detailOf('pave-floresta-negra-com-creme-danete');
export const catalog = () => new Map<string, Ingredient>(t('ingredients').map((i) => [i.id, i]));
export const tables = t;
