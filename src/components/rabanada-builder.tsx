'use client';

import Link from 'next/link';
import { useMemo, useState } from 'react';
import { Check, CookingPot, Flame, Sandwich, Sparkles } from 'lucide-react';
import type { Recipe, RecipeComponent } from '@/lib/types';
import {
  getRabanadaBaseRecipes,
  getRabanadaCommonPreparations,
  getRabanadaComposition,
  getRabanadaVariationsForBase,
} from '@/lib/rabanada-builder';
import { AddToPlanSheet } from './add-to-plan';
import { useSession } from '@/data/session';

/**
 * MONTE SUA RABANADA — usa os vínculos de componentes já registrados em cada variação.
 * Não cria combinações por semelhança de títulos nem depende de compatibilidades não verificadas.
 */
export function RabanadaBuilder({ recipes, components }: { recipes: Recipe[]; components: RecipeComponent[] }) {
  const { access, user } = useSession();
  const bases = useMemo(() => getRabanadaBaseRecipes(recipes, components), [recipes, components]);
  const [baseId, setBaseId] = useState<string | null>(null);
  const [variationId, setVariationId] = useState<string | null>(null);
  const [planning, setPlanning] = useState(false);

  const base = bases.find((recipe) => recipe.id === baseId) ?? null;
  const variations = useMemo(
    () => (base ? getRabanadaVariationsForBase(base.id, recipes, components) : []),
    [base, recipes, components],
  );
  const commonPreparations = useMemo(
    () => (base ? getRabanadaCommonPreparations(base.id, recipes, components) : []),
    [base, recipes, components],
  );
  const variation = variations.find((recipe) => recipe.id === variationId) ?? null;
  const composition = useMemo(
    () => (variation ? getRabanadaComposition(variation.id, recipes, components) : []),
    [variation, recipes, components],
  );
  const compositionLabels = composition.map(
    ({ component: part, linkedRecipe }) => linkedRecipe?.title ?? part.title,
  );

  if (!bases.length) return null;

  const option = (recipe: Recipe, selected: boolean, onSelect: () => void, hint?: string) => (
    <button
      key={recipe.id}
      type="button"
      className={`filter ${selected ? 'active' : ''}`}
      onClick={onSelect}
      aria-pressed={selected}
      style={{ whiteSpace: 'normal', textAlign: 'left', borderRadius: 14 }}
    >
      {selected && <Check size={14} style={{ marginRight: 6, verticalAlign: -2 }} />}
      {recipe.title}
      {hint && <span style={{ opacity: 0.7 }}> · {hint}</span>}
    </button>
  );

  const baseHint = (recipe: Recipe) => {
    const flavors = new Set(
      getRabanadaVariationsForBase(recipe.id, recipes, components)
        .map((item) => item.flavor)
        .filter((flavor): flavor is 'doce' | 'salgado' => flavor !== null),
    );
    return flavors.size === 1 ? [...flavors][0] : undefined;
  };

  return (
    <section className="panel" style={{ marginBottom: 22, background: 'linear-gradient(160deg,#fffdf6,#fff)' }}>
      <div className="eyebrow">✦ Experiência interativa</div>
      <h2 style={{ margin: '6px 0 4px' }}>Monte sua rabanada</h2>
      <p className="sub">Escolha uma massa e veja somente as variações e os preparos vinculados a ela no material cadastrado.</p>

      <div className="stack" style={{ marginTop: 18 }}>
        <div>
          <div className="parthead"><span className="partnum">1</span><h3>Escolha a massa do pão</h3></div>
          <div className="chips">
            {bases.map((item) =>
              option(item, item.id === baseId, () => {
                setBaseId(item.id);
                setVariationId(null);
              }, baseHint(item)),
            )}
          </div>
        </div>

        {base && commonPreparations.length > 0 && (
          <div>
            <div className="parthead"><span className="partnum">2</span><h3>Preparos comuns às variações</h3></div>
            <p className="sub small">Exibimos apenas caldas e preparos de fritura presentes em todas as variações desta massa.</p>
            <div className="chips">
              {commonPreparations.map((recipe) => {
                const role = components.find(
                  (part) =>
                    part.linked_recipe_id === recipe.id &&
                    variations.some((item) => item.id === part.recipe_id),
                )?.role;
                return (
                  <Link key={recipe.id} href={`/receitas/${recipe.slug}`} className="pill gold" style={{ padding: '8px 12px', fontSize: 13 }}>
                    {role === 'fritura' ? <Flame /> : <CookingPot />} {recipe.title}
                  </Link>
                );
              })}
            </div>
          </div>
        )}

        {base && (
          <div>
            <div className="parthead"><span className="partnum">{commonPreparations.length ? 3 : 2}</span><h3>Escolha a variação</h3></div>
            {variations.length ? (
              <div className="chips">
                {variations.map((item) =>
                  option(item, item.id === variationId, () => setVariationId(item.id)),
                )}
              </div>
            ) : (
              <p className="sub small">Nenhuma variação está vinculada a esta massa no cadastro atual.</p>
            )}
          </div>
        )}

        {base && variation && (
          <div className="calc">
            <div className="grow">
              <div className="eyebrow">Sua combinação</div>
              <h3 style={{ marginTop: 4 }}>
                <Sandwich size={17} style={{ verticalAlign: -3, marginRight: 6 }} />
                {variation.title}
              </h3>
              <span className="muted small">{compositionLabels.join(' + ')}</span>
            </div>
            <div className="row">
              <Link href={`/receitas/${variation.slug}`} className="btn outline sm">Abrir ficha</Link>
              {user && access.has_access && (
                <button type="button" className="btn dark sm" onClick={() => setPlanning(true)}>
                  <Sparkles /> Adicionar à ceia
                </button>
              )}
            </div>
          </div>
        )}
      </div>
      {planning && variation && <AddToPlanSheet recipe={variation} factor={1} onClose={() => setPlanning(false)} />}
    </section>
  );
}
