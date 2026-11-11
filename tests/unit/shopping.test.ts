import { describe, expect, it } from 'vitest';
import { applyRecipeToList, groupByCategory, itemQuantityLabel, linesFromRecipe, mergeKey, parseManualItem, removeRecipeFromList, shareText } from '@/lib/shopping';
import type { ShoppingItem } from '@/lib/types';
import { catalog, pave } from './fixtures';

let seq = 0;
/** Aplica uma mudança em memória, como o banco faria. */
function apply(items: ShoppingItem[], change: ReturnType<typeof applyRecipeToList>): ShoppingItem[] {
  const next = items.filter((i) => !change.deletes.includes(i.id)).map((i) => ({ ...i, ...(change.updates.find((u) => u.id === i.id)?.patch ?? {}) }));
  for (const insert of change.inserts) {
    next.push({
      id: `item-${++seq}`, list_id: 'l1', user_id: 'u1', is_checked: false, checked_at: null, quantity_edited: false, note: null,
      created_at: '', updated_at: '', ...insert,
    });
  }
  return next;
}
const find = (items: ShoppingItem[], name: string) => items.filter((i) => i.name === name);

describe('lista de compras', () => {
  const detail = pave();
  const lines = linesFromRecipe(detail, 1, catalog());

  it('gera as linhas da receita sem itens que não se compram (água)', () => {
    expect(lines).toHaveLength(11);
    expect(lines.find((l) => l.name === 'Água')).toBeUndefined();
    expect(lines.find((l) => l.name === 'Leite condensado')).toMatchObject({ quantity: 600, unit: 'g', category: 'laticinios' });
    expect(lines.find((l) => l.name === 'Granulé')).toMatchObject({ quantity: null, unit: null, quantity_text: 'quantidade não informada' });
  });

  it('não confunde creme de leite de caixinha com creme de leite fresco', () => {
    const uht = lines.find((l) => l.name === 'Creme de leite (caixinha)');
    const fresco = lines.find((l) => l.name === 'Creme de leite fresco');
    expect(uht).toMatchObject({ quantity: 400, unit: 'g' });
    expect(fresco).toMatchObject({ quantity: 300, unit: 'ml' });
    expect(mergeKey(uht!)).not.toBe(mergeKey(fresco!));
  });

  it('adicionar a mesma receita duas vezes não duplica quantidades', () => {
    let items = apply([], applyRecipeToList([], lines, detail.recipe.id));
    expect(items).toHaveLength(11);
    const again = applyRecipeToList(items, lines, detail.recipe.id);
    expect(again.inserts).toHaveLength(0);
    expect(again.deletes).toHaveLength(0);
    items = apply(items, again);
    expect(find(items, 'Leite condensado')[0].quantity).toBe(600);
  });

  it('mudar o fator substitui a contribuição anterior da receita', () => {
    let items = apply([], applyRecipeToList([], lines, detail.recipe.id));
    items = apply(items, applyRecipeToList(items, linesFromRecipe(detail, 2, catalog()), detail.recipe.id));
    expect(items).toHaveLength(11);
    expect(find(items, 'Leite condensado')[0]).toMatchObject({ quantity: 1200, unit: 'g' });
    expect(find(items, 'Leite condensado')[0].sources).toEqual([
      { recipe_id: detail.recipe.id, recipe_title: detail.recipe.title, quantity: 1200, unit: 'g', factor: 2 },
    ]);
  });

  it('soma somente o mesmo ingrediente na mesma unidade', () => {
    const other = { ...detail, recipe: { ...detail.recipe, id: 'outra', title: 'Outra receita' } };
    const otherLines = linesFromRecipe(other, 1, catalog()).map((l) =>
      l.name === 'Leite' ? { ...l, quantity: 2, unit: 'xícara', source: { ...l.source, quantity: 2, unit: 'xícara' } } : l,
    );
    let items = apply([], applyRecipeToList([], lines, detail.recipe.id));
    items = apply(items, applyRecipeToList(items, otherLines, 'outra'));
    // mesma unidade → soma
    expect(find(items, 'Leite condensado')).toHaveLength(1);
    expect(find(items, 'Leite condensado')[0].quantity).toBe(1200);
    expect(find(items, 'Leite condensado')[0].sources).toHaveLength(2);
    // unidades diferentes (ml × xícara) → itens separados, sem conversão
    const leite = find(items, 'Leite');
    expect(leite).toHaveLength(2);
    expect(leite.map((i) => itemQuantityLabel(i)).sort()).toEqual(['2 xícaras', '500 ml']);
    // textual com textual → um item só, sem inventar quantidade
    expect(find(items, 'Granulé')).toHaveLength(1);
    expect(find(items, 'Granulé')[0].quantity).toBeNull();
  });

  it('remover uma receita desfaz só a parte dela e preserva itens manuais', () => {
    const other = { ...detail, recipe: { ...detail.recipe, id: 'outra', title: 'Outra receita' } };
    let items = apply([], applyRecipeToList([], lines, detail.recipe.id));
    items = apply(items, applyRecipeToList(items, linesFromRecipe(other, 1, catalog()), 'outra'));
    items.push({ ...items[0], id: 'manual', name: 'Guardanapos', ingredient_id: null, quantity: null, unit: null, quantity_text: null, sources: [], is_manual: true });
    items = apply(items, removeRecipeFromList(items, 'outra'));
    expect(find(items, 'Leite condensado')[0].quantity).toBe(600);
    expect(find(items, 'Guardanapos')).toHaveLength(1);
    items = apply(items, removeRecipeFromList(items, detail.recipe.id));
    expect(items.map((i) => i.name)).toEqual(['Guardanapos']);
  });

  it('item já comprado volta a ficar pendente quando a quantidade aumenta', () => {
    const other = { ...detail, recipe: { ...detail.recipe, id: 'outra', title: 'Outra receita' } };
    let items: ShoppingItem[] = apply([], applyRecipeToList([], lines, detail.recipe.id)).map((i) => ({ ...i, is_checked: true, checked_at: 'x' }));
    items = apply(items, applyRecipeToList(items, linesFromRecipe(other, 1, catalog()), 'outra'));
    expect(find(items, 'Leite condensado')[0]).toMatchObject({ quantity: 1200, is_checked: false });
    // textual não muda de quantidade: continua marcado
    expect(find(items, 'Granulé')[0].is_checked).toBe(true);
  });

  it('agrupa por categoria e gera o texto para compartilhar', () => {
    const items = apply([], applyRecipeToList([], lines, detail.recipe.id));
    const groups = groupByCategory(items);
    expect(groups.map((g) => g.label)).toEqual(['Hortifruti', 'Laticínios', 'Mercearia', 'Confeitaria']);
    const text = shareText(items, 'Ceia em Família');
    expect(text).toContain('Lista de compras — Ceia em Família');
    expect(text).toContain('LATICÍNIOS');
    expect(text).toContain('☐ Leite condensado — 600 g');
    expect(text).toContain('☐ Granulé — quantidade não informada');
  });

  it('interpreta itens digitados manualmente', () => {
    expect(parseManualItem('2 kg de farinha de trigo')).toEqual({ name: 'Farinha de trigo', quantity: 2, unit: 'kg' });
    expect(parseManualItem('12 ovos')).toEqual({ name: 'Ovos', quantity: 12, unit: null });
    expect(parseManualItem('3 latas de leite condensado')).toEqual({ name: 'Leite condensado', quantity: 3, unit: 'lata' });
    expect(parseManualItem('2 limões')).toEqual({ name: 'Limões', quantity: 2, unit: null });
    expect(parseManualItem('1,5 l de leite')).toEqual({ name: 'Leite', quantity: 1.5, unit: 'l' });
    expect(parseManualItem('guardanapos')).toEqual({ name: 'Guardanapos', quantity: null, unit: null });
    expect(parseManualItem('   ')).toBeNull();
  });
});
