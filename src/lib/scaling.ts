/**
 * Calculadora de porções.
 *
 * Regras (seção 6 do escopo):
 *   • ajusta a partir do rendimento ORIGINAL da ficha;
 *   • só multiplica quantidades numéricas — nunca converte unidades;
 *   • medidas textuais ("a gosto", "QN", "quantidade não informada") ficam como estão;
 *   • itens marcados como "manual" recebem o valor proporcional como sugestão,
 *     com aviso de validação culinária; itens "fixed" não mudam.
 */
import type { Recipe, RecipeIngredient } from './types';
import { formatQuantity } from './format';

export const MIN_FACTOR = 0.25;
export const MAX_FACTOR = 20;

export function clampFactor(factor: number): number {
  if (!Number.isFinite(factor) || factor <= 0) return 1;
  return Math.min(MAX_FACTOR, Math.max(MIN_FACTOR, Math.round(factor * 1000) / 1000));
}

export type ScaleStatus = 'original' | 'scaled' | 'textual' | 'fixed' | 'needs_validation';

export interface ScaledIngredient {
  ingredient: RecipeIngredient;
  quantity: number | null;
  quantityMax: number | null;
  /** quantidade pronta para exibir: "1.200 g", "2 pacotes", "quantidade não informada" */
  text: string;
  status: ScaleStatus;
  /** aviso para a pessoa (por que não ajustou, ou que precisa validar) */
  note: string | null;
  /** equivalência caseira original — só faz sentido na receita sem ajuste */
  householdNote: string | null;
}

export function scaleIngredient(ingredient: RecipeIngredient, rawFactor: number): ScaledIngredient {
  const factor = clampFactor(rawFactor);
  const adjusted = Math.abs(factor - 1) > 1e-9;
  const base = { ingredient, householdNote: adjusted ? null : ingredient.household_note };

  if (ingredient.quantity == null) {
    return {
      ...base,
      quantity: null,
      quantityMax: null,
      text: ingredient.quantity_text ?? 'a gosto',
      status: 'textual',
      note: adjusted ? 'Medida textual no original: ajuste a gosto.' : null,
    };
  }

  const originalText = formatQuantity(ingredient.quantity, ingredient.unit, ingredient.quantity_max);

  if (ingredient.scaling === 'fixed') {
    return {
      ...base,
      householdNote: ingredient.household_note,
      quantity: ingredient.quantity,
      quantityMax: ingredient.quantity_max,
      text: originalText,
      status: 'fixed',
      note: adjusted ? 'Quantidade fixa: não acompanha o ajuste de porções.' : null,
    };
  }

  if (!adjusted) {
    return { ...base, quantity: ingredient.quantity, quantityMax: ingredient.quantity_max, text: originalText, status: 'original', note: null };
  }

  const quantity = ingredient.quantity * factor;
  const quantityMax = ingredient.quantity_max != null ? ingredient.quantity_max * factor : null;
  const text = formatQuantity(quantity, ingredient.unit, quantityMax);

  if (ingredient.scaling === 'manual') {
    return {
      ...base,
      quantity,
      quantityMax,
      text,
      status: 'needs_validation',
      note: `Sugestão proporcional — valide na prática (original: ${originalText}).`,
    };
  }

  return {
    ...base,
    quantity,
    quantityMax,
    text,
    status: 'scaled',
    note: ingredient.household_note ? `No original: ${originalText} (${ingredient.household_note}).` : null,
  };
}

export interface YieldControl {
  /** servings: a ficha informa porções · yield: informa outro rendimento (ex.: travessa) · batch: nada informado */
  mode: 'servings' | 'yield' | 'batch';
  base: number;
  unit: string;
  unitPlural: string;
  step: number;
  min: number;
  max: number;
}

export function yieldControl(recipe: Pick<Recipe, 'servings' | 'yield_quantity' | 'yield_unit' | 'yield_unit_plural'>): YieldControl {
  if (recipe.servings) {
    return { mode: 'servings', base: recipe.servings, unit: 'porção', unitPlural: 'porções', step: 1, min: 1, max: recipe.servings * MAX_FACTOR };
  }
  if (recipe.yield_quantity && recipe.yield_unit) {
    return {
      mode: 'yield',
      base: recipe.yield_quantity,
      unit: recipe.yield_unit,
      unitPlural: recipe.yield_unit_plural ?? recipe.yield_unit,
      step: recipe.yield_quantity / 2,
      min: recipe.yield_quantity / 2,
      max: recipe.yield_quantity * MAX_FACTOR,
    };
  }
  return { mode: 'batch', base: 1, unit: 'receita', unitPlural: 'receitas', step: 0.5, min: 0.5, max: MAX_FACTOR };
}

export const factorFromTarget = (control: YieldControl, target: number) => clampFactor(target / control.base);
export const targetFromFactor = (control: YieldControl, factor: number) => Math.round(control.base * clampFactor(factor) * 100) / 100;

export function describeYield(recipe: Pick<Recipe, 'servings' | 'yield_quantity' | 'yield_unit' | 'yield_unit_plural' | 'yield_detail' | 'yield_text'>, factor = 1): string | null {
  const control = yieldControl(recipe);
  if (control.mode === 'batch') return Math.abs(factor - 1) < 1e-9 ? recipe.yield_text : `${formatQuantity(factor, 'receita')}`;
  if (control.mode === 'servings') {
    const servings = targetFromFactor(control, factor);
    return formatQuantity(servings, 'porção');
  }
  const amount = formatQuantity(targetFromFactor(control, factor), recipe.yield_unit);
  return recipe.yield_detail ? `${amount} de ${recipe.yield_detail}` : amount;
}

export interface GuestSuggestion {
  factor: number;
  /** false quando a ficha não informa porções: não há como sugerir pela quantidade de convidados */
  basedOnServings: boolean;
  message: string;
}

/** Sugestão de fator para o planejamento. Só usa porções quando a ficha as informa. */
export function suggestFactorForGuests(recipe: Pick<Recipe, 'servings' | 'yield_quantity' | 'yield_unit' | 'yield_unit_plural' | 'yield_text'>, guests: number): GuestSuggestion {
  if (!recipe.servings) {
    return {
      factor: 1,
      basedOnServings: false,
      message: `O material não informa quantas porções rende${recipe.yield_text ? ` (rendimento original: ${recipe.yield_text})` : ''}. Ajuste a quantidade manualmente.`,
    };
  }
  const factor = clampFactor(Math.ceil((guests / recipe.servings) * 2) / 2);
  return {
    factor,
    basedOnServings: true,
    message: `${formatQuantity(factor, 'receita')} para ${guests} convidados (a ficha rende ${recipe.servings} porções).`,
  };
}
