/**
 * Lista de compras inteligente.
 *
 * Regras (seção 8 do escopo):
 *   • soma somente o mesmo ingrediente na MESMA unidade (nenhuma conversão automática);
 *   • medidas textuais não são somadas a medidas numéricas;
 *   • cada item guarda de quais receitas veio, para poder desfazer;
 *   • adicionar a mesma receita de novo substitui a contribuição anterior (não duplica).
 */
import type { Ingredient, RecipeDetail, ShoppingItem, ShoppingSource } from './types';
import { scaleIngredient } from './scaling';
import { formatQuantity, normalizeText } from './format';

export const CATEGORY_ORDER = ['hortifruti', 'laticinios', 'frios', 'carnes', 'padaria', 'mercearia', 'confeitaria', 'bebidas', 'despensa', 'outros'] as const;
export const CATEGORY_LABELS: Record<string, string> = {
  hortifruti: 'Hortifruti', laticinios: 'Laticínios', frios: 'Frios', carnes: 'Carnes', padaria: 'Padaria',
  mercearia: 'Mercearia', confeitaria: 'Confeitaria', bebidas: 'Bebidas', despensa: 'Despensa', outros: 'Outros',
};

export interface ShoppingLine {
  ingredient_id: string | null;
  name: string;
  category: string;
  quantity: number | null;
  unit: string | null;
  quantity_text: string | null;
  source: ShoppingSource;
}

type Mergeable = Pick<ShoppingLine, 'ingredient_id' | 'name' | 'quantity' | 'unit'>;

/** Dois itens só se somam quando têm a mesma chave: ingrediente + unidade (ou ambos textuais). */
export function mergeKey(item: Mergeable): string {
  const who = item.ingredient_id ?? `nome:${normalizeText(item.name)}`;
  const how = item.quantity == null ? 'texto' : item.unit ? `u:${normalizeText(item.unit)}` : 'sem-unidade';
  return `${who}|${how}`;
}

const capitalize = (text: string) => text.charAt(0).toLocaleUpperCase('pt-BR') + text.slice(1);

/** Linhas de compra de uma receita no fator escolhido (já somando repetições dentro da própria receita). */
export function linesFromRecipe(detail: RecipeDetail, factor: number, catalog: Map<string, Ingredient>): ShoppingLine[] {
  const lines = new Map<string, ShoppingLine>();
  for (const part of detail.parts) {
    for (const ingredient of part.ingredients) {
      const known = ingredient.ingredient_id ? catalog.get(ingredient.ingredient_id) : undefined;
      if (known && !known.is_shoppable) continue; // ex.: água
      const scaled = scaleIngredient(ingredient, factor);
      const line: ShoppingLine = {
        ingredient_id: ingredient.ingredient_id,
        name: known?.name ?? capitalize(ingredient.display_name),
        category: known?.category ?? 'outros',
        quantity: scaled.quantity,
        unit: scaled.quantity == null ? null : ingredient.unit,
        quantity_text: scaled.quantity == null ? scaled.text : null,
        source: { recipe_id: detail.recipe.id, recipe_title: detail.recipe.title, quantity: scaled.quantity, unit: ingredient.unit, factor },
      };
      const key = mergeKey(line);
      const existing = lines.get(key);
      if (existing && existing.quantity != null && line.quantity != null) {
        existing.quantity += line.quantity;
        existing.source = { ...existing.source, quantity: existing.quantity };
      } else if (!existing) {
        lines.set(key, line);
      }
    }
  }
  return [...lines.values()];
}

export type NewShoppingItem = Pick<ShoppingItem, 'ingredient_id' | 'name' | 'category' | 'quantity' | 'unit' | 'quantity_text' | 'sources' | 'is_manual' | 'position'>;

export interface ListChange {
  inserts: NewShoppingItem[];
  updates: { id: string; patch: Partial<ShoppingItem> }[];
  deletes: string[];
}

const round = (n: number) => Math.round(n * 1000) / 1000;

/** Retira a contribuição de uma receita, mantendo as linhas (para reaproveitá-las se a receita voltar). */
function stripRecipe(items: ShoppingItem[], recipeId: string): ShoppingItem[] {
  return items.map((item) => {
    const mine = item.sources.filter((s) => s.recipe_id === recipeId);
    if (!mine.length) return item;
    const removed = mine.reduce((sum, s) => sum + (s.quantity ?? 0), 0);
    return {
      ...item,
      sources: item.sources.filter((s) => s.recipe_id !== recipeId),
      quantity: item.quantity == null ? null : Math.max(0, round(item.quantity - removed)),
    };
  });
}

/** Itens que ficaram sem nenhuma receita de origem (e não são manuais) saem da lista. */
const prune = <T extends { sources: ShoppingSource[]; is_manual: boolean }>(items: T[]) => items.filter((i) => i.sources.length > 0 || i.is_manual);

function diff(before: ShoppingItem[], after: (ShoppingItem | NewShoppingItem)[]): ListChange {
  const change: ListChange = { inserts: [], updates: [], deletes: [] };
  const kept = new Set<string>();
  for (const item of after) {
    if (!('id' in item)) {
      change.inserts.push(item);
      continue;
    }
    kept.add(item.id);
    const original = before.find((b) => b.id === item.id);
    if (!original) continue;
    const patch: Partial<ShoppingItem> = {};
    if (original.quantity !== item.quantity) patch.quantity = item.quantity;
    if (original.is_checked !== item.is_checked) {
      patch.is_checked = item.is_checked;
      patch.checked_at = item.checked_at;
    }
    if (JSON.stringify(original.sources) !== JSON.stringify(item.sources)) patch.sources = item.sources;
    if (Object.keys(patch).length) change.updates.push({ id: item.id, patch });
  }
  change.deletes = before.filter((b) => !kept.has(b.id)).map((b) => b.id);
  return change;
}

/** Adiciona (ou atualiza) os ingredientes de uma receita na lista. */
export function applyRecipeToList(items: ShoppingItem[], lines: ShoppingLine[], recipeId: string): ListChange {
  const working: (ShoppingItem | NewShoppingItem)[] = stripRecipe(items, recipeId);
  let position = items.reduce((max, i) => Math.max(max, i.position), 0);

  for (const line of lines) {
    const key = mergeKey(line);
    const index = working.findIndex((w) => mergeKey(w) === key);
    if (index >= 0) {
      const current = working[index];
      working[index] = {
        ...current,
        quantity: current.quantity != null && line.quantity != null ? round(current.quantity + line.quantity) : current.quantity,
        sources: [...current.sources, line.source],
      };
    } else {
      working.push({
        ingredient_id: line.ingredient_id, name: line.name, category: line.category, quantity: line.quantity, unit: line.unit,
        quantity_text: line.quantity_text, sources: [line.source], is_manual: false, position: ++position,
      });
    }
  }

  const result = prune(working).map((item) => {
    if (!('id' in item)) return item;
    const original = items.find((i) => i.id === item.id);
    // se a quantidade a comprar aumentou, o item já marcado volta a ficar pendente
    const grew = original?.is_checked && item.quantity != null && original.quantity != null && item.quantity > original.quantity + 1e-9;
    return grew ? { ...item, is_checked: false, checked_at: null } : item;
  });
  return diff(items, result);
}

/** Remove da lista tudo o que veio de uma receita. */
export function removeRecipeFromList(items: ShoppingItem[], recipeId: string): ListChange {
  return diff(items, prune(stripRecipe(items, recipeId)));
}

export function itemQuantityLabel(item: Pick<ShoppingItem, 'quantity' | 'unit' | 'quantity_text'>): string {
  if (item.quantity != null) return formatQuantity(item.quantity, item.unit);
  return item.quantity_text ?? '';
}

export interface ShoppingGroup {
  category: string;
  label: string;
  items: ShoppingItem[];
}

export function groupByCategory(items: ShoppingItem[]): ShoppingGroup[] {
  const order = (c: string) => {
    const i = (CATEGORY_ORDER as readonly string[]).indexOf(c);
    return i < 0 ? CATEGORY_ORDER.length : i;
  };
  const groups = new Map<string, ShoppingItem[]>();
  for (const item of items) {
    const category = CATEGORY_LABELS[item.category] ? item.category : 'outros';
    groups.set(category, [...(groups.get(category) ?? []), item]);
  }
  return [...groups.entries()]
    .sort(([a], [b]) => order(a) - order(b))
    .map(([category, list]) => ({
      category,
      label: CATEGORY_LABELS[category],
      items: list.sort((a, b) => Number(a.is_checked) - Number(b.is_checked) || a.name.localeCompare(b.name, 'pt-BR')),
    }));
}

export function shareText(items: ShoppingItem[], title: string): string {
  const lines = [`Lista de compras — ${title}`];
  for (const group of groupByCategory(items)) {
    lines.push('', group.label.toUpperCase());
    for (const item of group.items) {
      const quantity = itemQuantityLabel(item);
      lines.push(`${item.is_checked ? '☑' : '☐'} ${item.name}${quantity ? ` — ${quantity}` : ''}`);
    }
  }
  lines.push('', 'Clube da Ceia Perfeita');
  return lines.join('\n');
}

const UNIT_WORDS = 'kg|g|mg|ml|l|un|unidades?|pacotes?|latas?|caixas?|caixinhas?|d[úu]zias?|garrafas?|potes?|vidros?';

/** Interpreta um item digitado: "2 kg de farinha" → { quantity: 2, unit: 'kg', name: 'Farinha' } */
export function parseManualItem(text: string): { name: string; quantity: number | null; unit: string | null } | null {
  const clean = text.trim().replace(/\s+/g, ' ');
  if (!clean) return null;
  const match = clean.match(new RegExp(`^(\\d+(?:[.,]\\d+)?)\\s*(${UNIT_WORDS})?\\s+(?:de\\s+)?(.+)$`, 'i'));
  if (!match) return { name: capitalize(clean), quantity: null, unit: null };
  const quantity = Number(match[1].replace(',', '.'));
  let unit = match[2]?.toLowerCase() ?? null;
  if (unit === 'un') unit = 'unidade';
  else if (unit && unit.length > 2 && unit.endsWith('s')) unit = unit.slice(0, -1); // pacotes → pacote
  return { name: capitalize(match[3]), quantity, unit };
}
