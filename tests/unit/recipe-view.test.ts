import { describe, expect, it } from 'vitest';
import { assembleRecipeDetail } from '@/lib/recipe-view';

describe('montagem da ficha de receita', () => {
  const recipe = {
    id: 'recipe-1', title: 'Rabanada de teste', slug: 'rabanada-teste',
    source_page_start: 16, source_page_end: 16,
    created_at: '2026-01-01T00:00:00.000Z', updated_at: '2026-01-01T00:00:00.000Z',
  } as any;

  it('não perde ingredientes e etapas cadastrados diretamente na receita', () => {
    const detail = assembleRecipeDetail(recipe, {
      components: [],
      ingredients: [{
        id: 'ingredient-1', recipe_id: recipe.id, component_id: null, position: 1,
        display_name: 'Leite condensado', quantity: 395, quantity_max: null, unit: 'g',
        quantity_text: '395 g', scaling: 'linear',
      } as any],
      steps: [{
        id: 'step-1', recipe_id: recipe.id, component_id: null, position: 1,
        instruction: 'Misture os ingredientes e leve ao fogo.',
      } as any],
      stepIngredients: [], timers: [], notes: [], tags: [],
    });

    expect(detail.hasContent).toBe(true);
    expect(detail.parts).toHaveLength(1);
    expect(detail.parts[0].component.title).toBe('Preparo principal');
    expect(detail.parts[0].ingredients.map((item) => item.display_name)).toEqual(['Leite condensado']);
    expect(detail.parts[0].steps.map((step) => step.instruction)).toEqual(['Misture os ingredientes e leve ao fogo.']);
  });

  it('não mistura linhas de outras partes em um componente sem vínculo', () => {
    const detail = assembleRecipeDetail(recipe, {
      components: [{
        id: 'component-1', recipe_id: recipe.id, linked_recipe_id: null, role: 'recheio',
        title: 'Recheio', multiplier: 1, position: 1,
      } as any],
      ingredients: [
        { id: 'ingredient-1', recipe_id: recipe.id, component_id: 'component-1', position: 1, display_name: 'Nozes' } as any,
        { id: 'ingredient-2', recipe_id: recipe.id, component_id: null, position: 1, display_name: 'Açúcar' } as any,
      ],
      steps: [
        { id: 'step-1', recipe_id: recipe.id, component_id: 'component-1', position: 1, instruction: 'Prepare o recheio.' } as any,
        { id: 'step-2', recipe_id: recipe.id, component_id: null, position: 1, instruction: 'Finalize a rabanada.' } as any,
      ],
      stepIngredients: [], timers: [], notes: [], tags: [],
    });

    expect(detail.parts).toHaveLength(2);
    expect(detail.parts[0].ingredients.map((item) => item.display_name)).toEqual(['Nozes']);
    expect(detail.parts[0].steps.map((step) => step.instruction)).toEqual(['Prepare o recheio.']);
    expect(detail.parts[1].ingredients.map((item) => item.display_name)).toEqual(['Açúcar']);
    expect(detail.parts[1].steps.map((step) => step.instruction)).toEqual(['Finalize a rabanada.']);
  });
});
