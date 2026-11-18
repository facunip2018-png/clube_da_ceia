import { describe, expect, it } from 'vitest';
import {
  getRabanadaPreparations,
  getVerifiedRabanadaBases,
  getVerifiedRabanadaFillings,
} from '@/lib/rabanada-builder';
import type { Recipe, RecipeComponent, RecipeCompatibility } from '@/lib/types';

function recipe(id: string, overrides: Partial<Recipe> = {}): Recipe {
  return {
    id,
    slug: id,
    collection_id: 'collection',
    source_document_id: 'source',
    kind: 'component',
    component_role: 'base',
    flavor: null,
    title: id,
    original_title: null,
    original_language: 'pt-BR',
    translation_status: 'not_needed',
    description: null,
    cover_image: null,
    difficulty: null,
    yield_quantity: null,
    yield_unit: null,
    yield_unit_plural: null,
    yield_detail: null,
    yield_text: null,
    servings: null,
    prep_minutes: null,
    cook_minutes: null,
    bake_minutes: null,
    chill_minutes: null,
    rest_minutes: null,
    chill_is_minimum: false,
    measure_note: null,
    source_page_start: null,
    source_page_end: null,
    source_pages_extra: [],
    page_ref_verified: true,
    content_state: 'structured',
    status: 'published',
    position: 0,
    is_featured: false,
    reviewed_by: null,
    reviewed_at: null,
    published_at: null,
    created_at: '2026-11-18T00:00:00.000Z',
    updated_at: '2026-11-18T00:00:00.000Z',
    ...overrides,
  };
}

function compatibility(
  id: string,
  baseId: string,
  fillingId: string,
  overrides: Partial<RecipeCompatibility> = {},
): RecipeCompatibility {
  return {
    id,
    recipe_id: baseId,
    compatible_recipe_id: fillingId,
    relation: 'recheio',
    source_page: 14,
    verified: true,
    note: 'Conferido na fonte.',
    created_at: '2026-11-18T00:00:00.000Z',
    ...overrides,
  };
}

function component(
  id: string,
  variationId: string,
  role: RecipeComponent['role'],
  linkedRecipeId: string | null,
  position: number,
): RecipeComponent {
  return {
    id,
    recipe_id: variationId,
    linked_recipe_id: linkedRecipeId,
    role,
    title: id,
    original_title: null,
    description: null,
    multiplier: 1,
    position,
    source_page_start: null,
    source_page_end: null,
    created_at: '2026-11-18T00:00:00.000Z',
    updated_at: '2026-11-18T00:00:00.000Z',
  };
}

describe('montador de rabanadas baseado em relações verificadas', () => {
  it('não transforma orientações gerais em bases selecionáveis', () => {
    const orientation = recipe('orientacao-doce', { source_page_start: 3 });
    const sweetBase = recipe('massa-doce', { source_page_start: 8 });
    const saltyBase = recipe('massa-salgada', { source_page_start: 9 });
    const recipes = [orientation, saltyBase, sweetBase];

    const rows = [
      compatibility('old', orientation.id, 'nutella', { verified: false }),
      compatibility('sweet', sweetBase.id, 'nutella'),
      compatibility('salty', saltyBase.id, 'gorgonzola'),
    ];

    expect(getVerifiedRabanadaBases(recipes, rows).map((item) => item.id)).toEqual(['massa-doce', 'massa-salgada']);
  });

  it('oferece somente variações publicadas e compatibilidades verificadas da base escolhida', () => {
    const nutella = recipe('nutella', { kind: 'variation', component_role: 'recheio', source_page_start: 14 });
    const doceDeLeite = recipe('doce-de-leite', { kind: 'variation', component_role: 'recheio', source_page_start: 15 });
    const draft = recipe('rascunho', { kind: 'variation', component_role: 'recheio', status: 'review' });
    const otherBase = recipe('massa-salgada', { source_page_start: 9 });
    const rows = [
      compatibility('valid', 'massa-doce', nutella.id),
      compatibility('unverified', 'massa-doce', doceDeLeite.id, { verified: false }),
      compatibility('draft', 'massa-doce', draft.id),
      compatibility('other-base', otherBase.id, 'gorgonzola'),
      compatibility('other-relation', 'massa-doce', 'cobertura', { relation: 'finalizacao' }),
    ];

    expect(getVerifiedRabanadaFillings('massa-doce', [nutella, doceDeLeite, draft], rows).map((item) => item.id)).toEqual(['nutella']);
  });

  it('mostra apenas os componentes vinculados à variação escolhida, na ordem cadastrada', () => {
    const linkedRecipes = [
      recipe('massa-doce'),
      recipe('calda-doce', { component_role: 'calda' }),
      recipe('fritura-doce', { component_role: 'fritura' }),
      recipe('recheio-compartilhado', { component_role: 'recheio' }),
      recipe('finalizacao', { component_role: 'finalizacao' }),
      recipe('rascunho', { status: 'review' }),
    ];
    const links = [
      component('massa', 'nutella', 'base', 'massa-doce', 0),
      component('calda', 'nutella', 'calda', 'calda-doce', 1),
      component('fritura', 'nutella', 'fritura', 'fritura-doce', 2),
      component('recheio', 'nutella', 'recheio', 'recheio-compartilhado', 3),
      component('finalizacao', 'nutella', 'finalizacao', 'finalizacao', 4),
      component('direto', 'nutella', 'recheio', null, 5),
      component('rascunho', 'nutella', 'cobertura', 'rascunho', 6),
      component('outra-variação', 'outra', 'base', 'massa-salgada', 0),
    ];

    expect(getRabanadaPreparations('nutella', linkedRecipes, links).map((item) => item.recipe.id)).toEqual([
      'massa-doce',
      'calda-doce',
      'fritura-doce',
      'recheio-compartilhado',
      'finalizacao',
    ]);
  });
});
