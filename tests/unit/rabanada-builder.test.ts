import { describe, expect, it } from 'vitest';
import type { Recipe, RecipeComponent } from '@/lib/types';
import {
  getRabanadaBaseRecipes,
  getRabanadaCommonPreparations,
  getRabanadaComposition,
  getRabanadaVariationsForBase,
} from '@/lib/rabanada-builder';

function makeRecipe(
  id: string,
  kind: Recipe['kind'],
  componentRole: Recipe['component_role'] = null,
  flavor: Recipe['flavor'] = null,
): Recipe {
  return { id, slug: id, title: id, kind, component_role: componentRole, flavor } as unknown as Recipe;
}

function makeComponent(
  recipeId: string,
  role: RecipeComponent['role'],
  linkedRecipeId: string | null,
  position: number,
): RecipeComponent {
  return {
    id: `${recipeId}-${role}-${position}`,
    recipe_id: recipeId,
    linked_recipe_id: linkedRecipeId,
    role,
    title: `${role}-${position}`,
    multiplier: 1,
    position,
  } as RecipeComponent;
}

describe('montador de rabanadas baseado na composição registrada', () => {
  const guidanceSweet = makeRecipe('guidance-sweet', 'component', 'base', 'doce');
  const guidanceSavory = makeRecipe('guidance-savory', 'component', 'base', 'salgado');
  const sweetBase = makeRecipe('sweet-base', 'component', 'base');
  const savoryBase = makeRecipe('savory-base', 'component', 'base');
  const sweetOne = makeRecipe('sweet-one', 'variation', null, 'doce');
  const sweetTwo = makeRecipe('sweet-two', 'variation', null, 'doce');
  const savoryOne = makeRecipe('savory-one', 'variation', null, 'salgado');
  const savoryTwo = makeRecipe('savory-two', 'variation', null, 'salgado');
  const syrup = makeRecipe('sweet-syrup', 'component', 'calda');
  const sweetFry = makeRecipe('sweet-fry', 'component', 'fritura');
  const savoryFry = makeRecipe('savory-fry', 'component', 'fritura');
  const sugarFinish = makeRecipe('sugar-finish', 'component', 'finalizacao');
  const powderFinish = makeRecipe('powder-finish', 'component', 'finalizacao');
  const recipes = [
    guidanceSweet, guidanceSavory, sweetBase, savoryBase,
    sweetOne, sweetTwo, savoryOne, savoryTwo,
    syrup, sweetFry, savoryFry, sugarFinish, powderFinish,
  ];

  const components = [
    makeComponent('sweet-one', 'base', 'sweet-base', 0),
    makeComponent('sweet-one', 'calda', 'sweet-syrup', 1),
    makeComponent('sweet-one', 'fritura', 'sweet-fry', 2),
    makeComponent('sweet-one', 'recheio', null, 3),
    makeComponent('sweet-one', 'finalizacao', 'sugar-finish', 4),
    makeComponent('sweet-two', 'base', 'sweet-base', 0),
    makeComponent('sweet-two', 'calda', 'sweet-syrup', 1),
    makeComponent('sweet-two', 'fritura', 'sweet-fry', 2),
    makeComponent('sweet-two', 'finalizacao', 'powder-finish', 3),
    makeComponent('savory-one', 'base', 'savory-base', 0),
    makeComponent('savory-one', 'fritura', 'savory-fry', 1),
    makeComponent('savory-two', 'base', 'savory-base', 0),
    makeComponent('savory-two', 'fritura', 'savory-fry', 1),
  ];

  it('exibe apenas massas referenciadas por uma variação, não orientações antigas', () => {
    expect(getRabanadaBaseRecipes(recipes, components).map((recipe) => recipe.id)).toEqual([
      'sweet-base',
      'savory-base',
    ]);
  });

  it('obtém as variações pela ligação explícita do componente de base', () => {
    expect(getRabanadaVariationsForBase('sweet-base', recipes, components).map((recipe) => recipe.id)).toEqual([
      'sweet-one',
      'sweet-two',
    ]);
    expect(getRabanadaVariationsForBase('savory-base', recipes, components).map((recipe) => recipe.id)).toEqual([
      'savory-one',
      'savory-two',
    ]);
  });

  it('mostra somente calda e fritura comuns a todas as variações da massa', () => {
    expect(getRabanadaCommonPreparations('sweet-base', recipes, components).map((recipe) => recipe.id)).toEqual([
      'sweet-syrup',
      'sweet-fry',
    ]);
    expect(getRabanadaCommonPreparations('savory-base', recipes, components).map((recipe) => recipe.id)).toEqual([
      'savory-fry',
    ]);
  });

  it('mantém a ordem da composição e preserva partes sem ficha vinculada', () => {
    const composition = getRabanadaComposition('sweet-one', recipes, components);
    expect(composition.map(({ component }) => component.role)).toEqual([
      'base',
      'calda',
      'fritura',
      'recheio',
      'finalizacao',
    ]);
    expect(composition.map(({ linkedRecipe }) => linkedRecipe?.id ?? null)).toEqual([
      'sweet-base',
      'sweet-syrup',
      'sweet-fry',
      null,
      'sugar-finish',
    ]);
  });

  it('não inventa preparos comuns quando uma variação não compartilha a ligação', () => {
    const variantComponents = components.filter(
      (component) => !(component.recipe_id === 'sweet-two' && component.role === 'calda'),
    );
    expect(getRabanadaCommonPreparations('sweet-base', recipes, variantComponents).map((recipe) => recipe.id)).toEqual([
      'sweet-fry',
    ]);
  });
});
