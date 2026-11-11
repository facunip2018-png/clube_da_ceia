'use client';

import { useMemo } from 'react';
import useSWR, { mutate as globalMutate } from 'swr';
import type { CatalogStat, Collection, Ingredient, Recipe, RecipeDetail, TableName, Tables } from '@/lib/types';
import { assembleRecipeDetail } from '@/lib/recipe-view';
import { useSession } from './session';
import type { Query, Rpc, RpcName } from './store';

const SWR_OPTIONS = { revalidateOnFocus: false, shouldRetryOnError: false } as const;

/** Lê uma tabela respeitando as permissões da pessoa. Passe `null` como consulta para não buscar. */
export function useTable<K extends TableName>(table: K, query?: Query<Tables[K]> | null) {
  const { store, key, ready } = useSession();
  const enabled = ready && query !== null;
  const swr = useSWR(enabled ? ['t', table, JSON.stringify(query ?? {}), key] : null, () => store.list(table, query ?? {}), SWR_OPTIONS);
  return { rows: swr.data as Tables[K][] | undefined, error: swr.error as Error | undefined, loading: enabled ? swr.isLoading : !ready, mutate: swr.mutate };
}

export function useRpc<N extends RpcName>(name: N, enabled = true) {
  const { store, key, ready } = useSession();
  const on = ready && enabled;
  const swr = useSWR(on ? ['rpc', name, key] : null, () => store.rpc(name), SWR_OPTIONS);
  return { data: swr.data as Rpc[N]['result'] | undefined, error: swr.error as Error | undefined, loading: on ? swr.isLoading : !ready, mutate: swr.mutate };
}

/** Recarrega tudo o que depende das tabelas/funções informadas. */
export function invalidate(...names: (TableName | RpcName)[]) {
  return globalMutate((cacheKey) => Array.isArray(cacheKey) && names.includes(cacheKey[1]));
}

// ----------------------------------------------------------------------------
// Consultas compostas
// ----------------------------------------------------------------------------
export interface CollectionSummary {
  collection: Collection;
  /** receitas que a pessoa pode ver (publicadas; para o admin, todas) */
  recipes: Recipe[];
  stat: CatalogStat | null;
}

export function useCatalog() {
  const collections = useTable('collections', { order: [['position', 'asc']] });
  const recipes = useTable('recipes', { order: [['position', 'asc']] });
  const stats = useRpc('catalog_stats');
  const summaries = useMemo<CollectionSummary[]>(
    () =>
      (collections.rows ?? []).map((collection) => ({
        collection,
        recipes: (recipes.rows ?? []).filter((r) => r.collection_id === collection.id && r.status !== 'archived'),
        stat: stats.data?.find((s) => s.collection_id === collection.id) ?? null,
      })),
    [collections.rows, recipes.rows, stats.data],
  );
  return {
    summaries,
    collections: collections.rows ?? [],
    recipes: recipes.rows ?? [],
    stats: stats.data ?? [],
    loading: collections.loading || recipes.loading,
    error: collections.error ?? recipes.error,
  };
}

/** Ficha completa de uma receita. As partes premium só são buscadas quando a pessoa tem acesso. */
export function useRecipeDetail(recipe: Recipe | null | undefined): { detail: RecipeDetail | null; loading: boolean } {
  const { access } = useSession();
  const canReadContent = Boolean(recipe && access.has_access);
  const id = recipe?.id ?? '';
  const components = useTable('recipe_components', canReadContent ? { eq: { recipe_id: id } } : null);
  const linkedIds = useMemo(() => (components.rows ?? []).map((c) => c.linked_recipe_id).filter((v): v is string => Boolean(v)), [components.rows]);
  const scope = canReadContent && components.rows ? { in: { recipe_id: [id, ...linkedIds] } } : null;
  const ingredients = useTable('recipe_ingredients', scope);
  const steps = useTable('recipe_steps', scope);
  const stepIngredients = useTable('recipe_step_ingredients', scope);
  const timers = useTable('recipe_step_timers', scope);
  const notes = useTable('recipe_notes', canReadContent ? { eq: { recipe_id: id } } : null);
  const tags = useTable('recipe_tags', recipe ? { eq: { recipe_id: id } } : null);
  const collections = useTable('collections', recipe ? { eq: { id: recipe.collection_id } } : null);
  const sources = useTable('source_document_refs', recipe?.source_document_id ? { eq: { id: recipe.source_document_id } } : null);
  // a administração enxerga a origem mesmo antes da publicação
  const adminSources = useTable('source_documents', access.is_admin && recipe?.source_document_id ? { eq: { id: recipe.source_document_id } } : null);

  const loading = Boolean(recipe) && canReadContent && (!components.rows || !ingredients.rows || !steps.rows || !stepIngredients.rows || !timers.rows || !notes.rows);

  const detail = useMemo(() => {
    if (!recipe) return null;
    return assembleRecipeDetail(
      recipe,
      {
        components: components.rows ?? [],
        ingredients: ingredients.rows ?? [],
        steps: steps.rows ?? [],
        stepIngredients: stepIngredients.rows ?? [],
        timers: timers.rows ?? [],
        notes: notes.rows ?? [],
        tags: tags.rows ?? [],
      },
      { collection: collections.rows?.[0] ?? null, source: sources.rows?.[0] ?? adminSources.rows?.[0] ?? null },
    );
  }, [recipe, components.rows, ingredients.rows, steps.rows, stepIngredients.rows, timers.rows, notes.rows, tags.rows, collections.rows, sources.rows, adminSources.rows]);

  return { detail, loading };
}

/** Fichas completas de várias receitas (cardápio da ceia, Chef IA). */
export function useRecipeDetails(recipes: Recipe[]): { details: RecipeDetail[]; loading: boolean } {
  const { access } = useSession();
  const ids = useMemo(() => recipes.map((r) => r.id).sort(), [recipes]);
  const scope = access.has_access && ids.length ? { in: { recipe_id: ids } } : null;
  const components = useTable('recipe_components', scope);
  const ingredients = useTable('recipe_ingredients', scope);
  const steps = useTable('recipe_steps', scope);
  const stepIngredients = useTable('recipe_step_ingredients', scope);
  const timers = useTable('recipe_step_timers', scope);
  const notes = useTable('recipe_notes', scope);
  const tags = useTable('recipe_tags', ids.length ? { in: { recipe_id: ids } } : null);
  const collections = useTable('collections');
  const loading = Boolean(scope) && (!components.rows || !ingredients.rows || !steps.rows || !stepIngredients.rows || !timers.rows || !notes.rows);

  const details = useMemo(
    () =>
      recipes.map((recipe) =>
        assembleRecipeDetail(
          recipe,
          {
            components: components.rows ?? [],
            ingredients: ingredients.rows ?? [],
            steps: steps.rows ?? [],
            stepIngredients: stepIngredients.rows ?? [],
            timers: timers.rows ?? [],
            notes: notes.rows ?? [],
            tags: tags.rows ?? [],
          },
          { collection: collections.rows?.find((c) => c.id === recipe.collection_id) ?? null },
        ),
      ),
    [recipes, components.rows, ingredients.rows, steps.rows, stepIngredients.rows, timers.rows, notes.rows, tags.rows, collections.rows],
  );
  return { details, loading };
}

export function useIngredientCatalog(): Map<string, Ingredient> {
  const { access } = useSession();
  const { rows } = useTable('ingredients', access.has_access ? {} : null);
  return useMemo(() => new Map((rows ?? []).map((i) => [i.id, i])), [rows]);
}

export function useFavoriteIds(): Set<string> {
  const { user } = useSession();
  const { rows } = useTable('recipe_favorites', user ? {} : null);
  return useMemo(() => new Set((rows ?? []).map((f) => f.recipe_id)), [rows]);
}
