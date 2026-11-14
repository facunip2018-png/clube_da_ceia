import { describe, expect, it } from 'vitest';
import { visibleRecipeCompatibilities } from '@/lib/recipe-compatibility';
import type { RecipeCompatibility } from '@/lib/types';

const compatibility = (id: string, verified: boolean): RecipeCompatibility => ({
  id,
  recipe_id: 'base-doce',
  compatible_recipe_id: `recheio-${id}`,
  relation: 'recheio',
  source_page: null,
  verified,
  note: verified ? null : 'Combinação ainda não conferida na fonte.',
  created_at: '2026-11-14T00:00:00.000Z',
});

describe('visibilidade das combinações de rabanadas', () => {
  const confirmed = compatibility('confirmada', true);
  const pending = compatibility('pendente', false);

  it('mostra ao cliente somente combinações verificadas', () => {
    expect(visibleRecipeCompatibilities([confirmed, pending], false)).toEqual([confirmed]);
  });

  it('não libera nenhuma combinação quando todas estão pendentes', () => {
    expect(visibleRecipeCompatibilities([pending], false)).toEqual([]);
  });

  it('mantém as combinações pendentes disponíveis apenas na prévia administrativa', () => {
    expect(visibleRecipeCompatibilities([confirmed, pending], true)).toEqual([confirmed, pending]);
  });

  it('não altera a lista original recebida', () => {
    const rows = [confirmed, pending];
    visibleRecipeCompatibilities(rows, false);
    expect(rows).toEqual([confirmed, pending]);
  });
});
