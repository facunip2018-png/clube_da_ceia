import { describe, expect, it } from 'vitest';
import { clampFactor, describeYield, factorFromTarget, scaleIngredient, suggestFactorForGuests, yieldControl } from '@/lib/scaling';
import { formatClock, formatDuration, formatNumber, formatQuantity } from '@/lib/format';
import { flattenSteps, knownTimes } from '@/lib/recipe-view';
import { pave } from './fixtures';

const ingredient = (name: string) => {
  const found = pave().parts.flatMap((p) => p.ingredients).find((i) => i.display_name === name);
  if (!found) throw new Error(`ingrediente não encontrado: ${name}`);
  return found;
};

describe('formatação', () => {
  it('formata quantidades métricas em pt-BR sem converter unidades', () => {
    expect(formatQuantity(600, 'g')).toBe('600 g');
    expect(formatQuantity(1200, 'g')).toBe('1.200 g');
    expect(formatQuantity(37.5, 'ml')).toBe('38 ml');
    expect(formatQuantity(7.5, 'ml')).toBe('7,5 ml');
  });
  it('usa frações e plural em medidas caseiras', () => {
    expect(formatQuantity(1, 'pacote')).toBe('1 pacote');
    expect(formatQuantity(2, 'pacote')).toBe('2 pacotes');
    expect(formatQuantity(0.5, 'pacote')).toBe('½ pacote');
    expect(formatQuantity(1.5, 'xícara')).toBe('1 ½ xícara');
    expect(formatQuantity(2.5, 'xícara')).toBe('2 ½ xícaras');
    expect(formatNumber(0.3333)).toBe('⅓');
    expect(formatQuantity(1, 'colher (sopa)', 2)).toBe('1 a 2 colheres (sopa)');
  });
  it('formata tempos', () => {
    expect(formatDuration(240)).toBe('4 min');
    expect(formatDuration(21600)).toBe('6 h');
    expect(formatDuration(5400)).toBe('1 h 30 min');
    expect(formatClock(239_000)).toBe('03:59');
    expect(formatClock(21_600_000)).toBe('6:00:00');
  });
});

describe('ficha do Pavê Floresta Negra', () => {
  it('é montada em 3 partes, 12 ingredientes e 16 etapas, na ordem do material', () => {
    const detail = pave();
    expect(detail.parts.map((p) => p.component.title)).toEqual(['Creme Danete', 'Preparo para a montagem', 'Montagem']);
    expect(detail.parts.map((p) => p.ingredients.length)).toEqual([4, 6, 2]);
    expect(detail.parts.map((p) => p.steps.length)).toEqual([5, 5, 6]);
    expect(flattenSteps(detail)).toHaveLength(16);
    expect(detail.hasContent).toBe(true);
  });
  it('só informa os tempos que constam no material', () => {
    expect(knownTimes(pave().recipe)).toEqual([{ label: 'Geladeira', minutes: 360, minimum: true }]);
    const timers = pave().parts.flatMap((p) => p.steps.flatMap((s) => s.timers));
    expect(timers.map((t) => t.duration_seconds)).toEqual([240, 21600]);
  });
  it('liga cada etapa aos ingredientes e partes que utiliza', () => {
    const steps = flattenSteps(pave());
    const uses = (i: number) => steps[i].step.uses.map((u) => (u.type === 'ingredient' ? u.ingredient.display_name : `[${u.component.title}]`));
    expect(uses(0)).toEqual(['chocolate em pó', 'água']);
    expect(uses(10)).toEqual(['[Creme Danete]']);
    expect(uses(11)).toEqual(['bolacha champanhe', 'leite']);
    expect(uses(15)).toEqual(['granulé', 'brigadeiros', 'cerejas frescas']);
  });
});

describe('calculadora de porções', () => {
  it('mantém a receita original no fator 1, com a equivalência caseira', () => {
    const s = scaleIngredient(ingredient('leite condensado'), 1);
    expect(s).toMatchObject({ text: '600 g', status: 'original', householdNote: '1 lata e meia', note: null });
  });
  it('multiplica quantidades numéricas sem converter unidades', () => {
    expect(scaleIngredient(ingredient('leite condensado'), 2)).toMatchObject({ quantity: 1200, text: '1.200 g', status: 'scaled' });
    expect(scaleIngredient(ingredient('água'), 0.5)).toMatchObject({ quantity: 37.5, text: '38 ml' });
    expect(scaleIngredient(ingredient('leite'), 3).text).toBe('1.500 ml'); // não vira 1,5 l
  });
  it('não recalcula a equivalência caseira ao ajustar: mostra a medida original', () => {
    const s = scaleIngredient(ingredient('leite condensado'), 2);
    expect(s.householdNote).toBeNull();
    expect(s.note).toBe('No original: 600 g (1 lata e meia).');
  });
  it('preserva medidas textuais (quantidade não informada / a gosto)', () => {
    const s = scaleIngredient(ingredient('granulé'), 3);
    expect(s).toMatchObject({ quantity: null, text: 'quantidade não informada', status: 'textual' });
    expect(s.note).toContain('ajuste a gosto');
  });
  it('sinaliza validação culinária em medidas que não podem ser convertidas (1 pacote)', () => {
    const s = scaleIngredient(ingredient('bolacha champanhe'), 2);
    expect(s).toMatchObject({ quantity: 2, text: '2 pacotes', status: 'needs_validation' });
    expect(s.note).toContain('valide na prática');
    expect(scaleIngredient(ingredient('bolacha champanhe'), 1).status).toBe('original');
  });
  it('respeita itens de quantidade fixa', () => {
    const fixed = { ...ingredient('leite'), scaling: 'fixed' as const };
    expect(scaleIngredient(fixed, 4)).toMatchObject({ quantity: 500, text: '500 ml', status: 'fixed' });
  });
  it('limita o fator a um intervalo seguro', () => {
    expect(clampFactor(0)).toBe(1);
    expect(clampFactor(NaN)).toBe(1);
    expect(clampFactor(0.1)).toBe(0.25);
    expect(clampFactor(99)).toBe(20);
  });
  it('sem porções informadas, ajusta por rendimento (travessas) e não por pessoas', () => {
    const { recipe } = pave();
    const control = yieldControl(recipe);
    expect(control).toMatchObject({ mode: 'yield', base: 1, unit: 'travessa', unitPlural: 'travessas', step: 0.5, min: 0.5 });
    expect(factorFromTarget(control, 2)).toBe(2);
    expect(describeYield(recipe, 1)).toBe('1 travessa de 27 × 17 cm');
    expect(describeYield(recipe, 2)).toBe('2 travessas de 27 × 17 cm');
    expect(describeYield(recipe, 1.5)).toBe('1 ½ travessa de 27 × 17 cm');
    const suggestion = suggestFactorForGuests(recipe, 20);
    expect(suggestion).toMatchObject({ factor: 1, basedOnServings: false });
    expect(suggestion.message).toContain('não informa quantas porções');
  });
  it('com porções informadas, calcula o fator pelos convidados (arredondando para cima em meia receita)', () => {
    const recipe = { ...pave().recipe, servings: 8 };
    expect(yieldControl(recipe)).toMatchObject({ mode: 'servings', base: 8, step: 1 });
    expect(suggestFactorForGuests(recipe, 10)).toMatchObject({ factor: 1.5, basedOnServings: true });
    expect(suggestFactorForGuests(recipe, 16).factor).toBe(2);
    expect(describeYield(recipe, 1.5)).toBe('12 porções');
  });
});
