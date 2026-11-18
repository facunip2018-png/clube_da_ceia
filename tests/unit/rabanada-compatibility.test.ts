import { describe, expect, it } from 'vitest';
import type { RecipeCompatibility } from '@/lib/types';
import {
  pendingRabanadaCompatibilityCount,
  rabanadaBaseIds,
  rabanadaOptionIds,
  verifiedRabanadaCompatibilities,
} from '@/lib/rabanada-compatibility';

function compatibility(overrides: Partial<RecipeCompatibility> = {}): RecipeCompatibility {
  return {
    id: 'compat-1',
    recipe_id: 'base-doce',
    compatible_recipe_id: 'recheio-nutella',
    relation: 'recheio',
    source_page: 14,
    verified: false,
    note: 'Aguardando conferência da fonte.',
    created_at: '2026-11-18T00:00:00.000Z',
    ...overrides,
  };
}

describe('compatibilidade do montador de rabanadas', () => {
  it('não oferece combinações ainda não verificadas', () => {
    const rows = [
      compatibility({ id: 'pending' }),
      compatibility({ id: 'verified', compatible_recipe_id: 'recheio-doce-de-leite', verified: true }),
    ];

    expect(verifiedRabanadaCompatibilities(rows).map((item) => item.id)).toEqual(['verified']);
    expect(pendingRabanadaCompatibilityCount(rows)).toBe(1);
    expect(rabanadaOptionIds(rows, 'base-doce', 'recheio')).toEqual(new Set(['recheio-doce-de-leite']));
  });

  it('só disponibiliza bases que possuem ao menos uma combinação verificada', () => {
    const rows = [
      compatibility({ id: 'pending', recipe_id: 'base-sem-validacao' }),
      compatibility({ id: 'verified', recipe_id: 'base-doce', verified: true }),
    ];

    expect(rabanadaBaseIds(rows)).toEqual(new Set(['base-doce']));
  });

  it('não mistura relações diferentes nem opções de outra base', () => {
    const rows = [
      compatibility({ id: 'filling', verified: true }),
      compatibility({ id: 'finish', relation: 'finalizacao', compatible_recipe_id: 'finalizacao-acucar', verified: true }),
      compatibility({ id: 'other-base', recipe_id: 'base-salgada', compatible_recipe_id: 'recheio-gorgonzola', verified: true }),
    ];

    expect(rabanadaOptionIds(rows, 'base-doce', 'recheio')).toEqual(new Set(['recheio-nutella']));
    expect(rabanadaOptionIds(rows, 'base-doce', 'finalizacao')).toEqual(new Set(['finalizacao-acucar']));
    expect(rabanadaOptionIds(rows, 'base-salgada', 'recheio')).toEqual(new Set(['recheio-gorgonzola']));
  });

  it('não cria opções quando todas as relações estão pendentes', () => {
    const rows = [compatibility(), compatibility({ id: 'pending-2', compatible_recipe_id: 'recheio-pistache' })];

    expect(verifiedRabanadaCompatibilities(rows)).toEqual([]);
    expect(rabanadaBaseIds(rows)).toEqual(new Set());
    expect(rabanadaOptionIds(rows, 'base-doce', 'recheio')).toEqual(new Set());
    expect(pendingRabanadaCompatibilityCount(rows)).toBe(2);
  });
});
