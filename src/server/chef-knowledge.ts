/**
 * Base de conhecimento do Chef IA no servidor: busca as fichas PUBLICADAS com o
 * cliente da própria pessoa (RLS garante que só quem tem acesso válido lê o conteúdo).
 */
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Collection, Recipe, RecipeDetail, RecipeTag } from '@/lib/types';
import { assembleRecipeDetail, type RecipeRows } from '@/lib/recipe-view';
import { selectRelevant } from '@/lib/chef';

const PAGE = 1000;

async function all<T>(build: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: { message: string } | null }>, maxPages = 6): Promise<T[]> {
  const rows: T[] = [];
  for (let page = 0; page < maxPages; page++) {
    const { data, error } = await build(page * PAGE, page * PAGE + PAGE - 1);
    if (error) throw new Error(error.message);
    rows.push(...(data ?? []));
    if (!data || data.length < PAGE) break;
  }
  return rows;
}

export interface ChefKnowledge {
  relevant: RecipeDetail[];
  availableTitles: string[];
  recipes: Recipe[];
}

export async function loadChefKnowledge(supabase: SupabaseClient, question: string, focusRecipeId: string | null): Promise<ChefKnowledge> {
  const recipes = await all<Recipe>((from, to) => supabase.from('recipes').select('*').eq('status', 'published').order('position').range(from, to));
  if (!recipes.length) return { relevant: [], availableTitles: [], recipes };
  const ids = recipes.map((r) => r.id);

  // 1) índice leve (títulos, tags, nomes de ingredientes e de partes) para escolher as fichas relevantes
  const [tags, names, parts, collections] = await Promise.all([
    all<RecipeTag>((from, to) => supabase.from('recipe_tags').select('*').in('recipe_id', ids).range(from, to)),
    all<{ recipe_id: string; display_name: string }>((from, to) => supabase.from('recipe_ingredients').select('recipe_id, display_name').in('recipe_id', ids).range(from, to)),
    all<{ recipe_id: string; title: string }>((from, to) => supabase.from('recipe_components').select('recipe_id, title').in('recipe_id', ids).range(from, to)),
    all<Collection>((from, to) => supabase.from('collections').select('*').range(from, to)),
  ]);
  const index = recipes.map((recipe): RecipeDetail => ({
    recipe,
    collection: null,
    source: null,
    parts: [
      ...parts.filter((p) => p.recipe_id === recipe.id).map((p) => ({ component: { title: p.title }, ingredients: [], steps: [] })),
      { component: { title: '' }, ingredients: names.filter((n) => n.recipe_id === recipe.id), steps: [] },
    ] as never,
    tips: [], notes: [], equipment: [],
    tags: tags.filter((t) => t.recipe_id === recipe.id).map((t) => t.tag),
    hasContent: true,
  }));
  const chosen = selectRelevant(question, index, { focusRecipeId, limit: 3 }).map((d) => d.recipe);
  const availableTitles = recipes.map((r) => r.title);
  if (!chosen.length) return { relevant: [], availableTitles, recipes };

  // 2) fichas completas apenas das escolhidas
  const chosenIds = chosen.map((r) => r.id);
  const table = <T>(name: string) => all<T>((from, to) => supabase.from(name).select('*').in('recipe_id', chosenIds).range(from, to));
  const [components, ingredients, steps, stepIngredients, timers, notes] = await Promise.all([
    table<RecipeRows['components'][number]>('recipe_components'),
    table<RecipeRows['ingredients'][number]>('recipe_ingredients'),
    table<RecipeRows['steps'][number]>('recipe_steps'),
    table<RecipeRows['stepIngredients'][number]>('recipe_step_ingredients'),
    table<RecipeRows['timers'][number]>('recipe_step_timers'),
    table<RecipeRows['notes'][number]>('recipe_notes'),
  ]);
  const { data: sources } = await supabase.from('source_document_refs').select('*');
  const relevant = chosen
    .map((recipe) =>
      assembleRecipeDetail(recipe, { components, ingredients, steps, stepIngredients, timers, notes, tags }, {
        collection: collections.find((c) => c.id === recipe.collection_id) ?? null,
        source: (sources ?? []).find((s) => s.id === recipe.source_document_id) ?? null,
      }),
    )
    .filter((detail) => detail.hasContent);
  return { relevant, availableTitles, recipes };
}

/** Chama a API de respostas da OpenAI. A chave fica somente no servidor. */
export async function askOpenAI(request: { instructions: string; input: { role: string; content: string }[] }): Promise<{ text: string; model: string; tokensIn: number | null; tokensOut: number | null }> {
  const key = process.env.OPENAI_API_KEY;
  if (!key) throw new Error('OPENAI_API_KEY ausente');
  const model = process.env.OPENAI_MODEL || 'gpt-6-luna';
  const effort = process.env.OPENAI_REASONING_EFFORT;
  const response = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model,
      instructions: request.instructions,
      input: request.input,
      max_output_tokens: 1200,
      store: false,
      ...(effort ? { reasoning: { effort } } : {}),
    }),
    signal: AbortSignal.timeout(40_000),
  });
  if (!response.ok) throw new Error(`OpenAI respondeu ${response.status}`);
  const data = (await response.json()) as {
    output?: { type: string; content?: { type: string; text?: string }[] }[];
    usage?: { input_tokens?: number; output_tokens?: number };
  };
  const text = (data.output ?? [])
    .filter((item) => item.type === 'message')
    .flatMap((item) => item.content ?? [])
    .filter((part) => part.type === 'output_text' && part.text)
    .map((part) => part.text)
    .join('')
    .trim();
  if (!text) throw new Error('OpenAI devolveu uma resposta vazia');
  return { text, model, tokensIn: data.usage?.input_tokens ?? null, tokensOut: data.usage?.output_tokens ?? null };
}
