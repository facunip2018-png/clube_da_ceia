'use client';

import Link from 'next/link';
import { useMemo, useState } from 'react';
import { Check, CookingPot, Flame, Sandwich, Sparkles } from 'lucide-react';
import type { Recipe, RecipeCompatibility, RecipeComponent } from '@/lib/types';
import { getRabanadaPreparations, getVerifiedRabanadaBases, getVerifiedRabanadaFillings } from '@/lib/rabanada-builder';
import { Notice } from './ui';
import { AddToPlanSheet } from './add-to-plan';
import { useSession } from '@/data/session';

/**
 * MONTE SUA RABANADA — só oferece relações verificadas na fonte.
 * Os preparos apresentados vêm dos componentes vinculados à variação escolhida.
 */
export function RabanadaBuilder({
  recipes,
  compatibilities,
  componentLinks,
}: {
  recipes: Recipe[];
  compatibilities: RecipeCompatibility[];
  componentLinks: RecipeComponent[];
}) {
  const { access, user } = useSession();
  const bases = useMemo(() => getVerifiedRabanadaBases(recipes, compatibilities), [recipes, compatibilities]);
  const [baseId, setBaseId] = useState<string | null>(null);
  const [fillingId, setFillingId] = useState<string | null>(null);
  const [planning, setPlanning] = useState(false);

  const base = bases.find((item) => item.id === baseId) ?? null;
  const fillings = useMemo(
    () => (base ? getVerifiedRabanadaFillings(base.id, recipes, compatibilities) : []),
    [base, recipes, compatibilities],
  );
  const filling = fillings.find((item) => item.id === fillingId) ?? null;
  const preparations = useMemo(
    () => (filling ? getRabanadaPreparations(filling.id, recipes, componentLinks) : []),
    [filling, recipes, componentLinks],
  );

  if (!bases.length) return null;

  const option = (recipe: Recipe, selected: boolean, onSelect: () => void) => (
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
    </button>
  );

  const composition = base && filling
    ? [
        base.title,
        ...preparations.filter((item) => item.recipe.id !== base.id).map((item) => item.component.title || item.recipe.title),
        filling.title,
      ].join(' + ')
    : '';

  return (
    <section className="panel" style={{ marginBottom: 22, background: 'linear-gradient(160deg,#fffdf6,#fff)' }}>
      <div className="eyebrow">✦ Experiência interativa</div>
      <h2 style={{ margin: '6px 0 4px' }}>Monte sua rabanada</h2>
      <p className="sub">Escolha uma massa de pão e uma variação confirmada na apostila. Os preparos vinculados à variação selecionada aparecem em seguida.</p>

      {access.is_admin && (
        <div style={{ marginTop: 14 }}>
          <Notice>
            <b>Curadoria:</b> o montador exibe apenas combinações marcadas como verificadas e mostra os componentes realmente vinculados à variação escolhida.
          </Notice>
        </div>
      )}

      <div className="stack" style={{ marginTop: 18 }}>
        <div>
          <div className="parthead"><span className="partnum">1</span><h3>Escolha a massa de pão</h3></div>
          <div className="chips">
            {bases.map((item) => option(item, item.id === baseId, () => {
              setBaseId(item.id);
              setFillingId(null);
            }))}
          </div>
        </div>

        {base && (
          <div>
            <div className="parthead"><span className="partnum">2</span><h3>Escolha a variação</h3></div>
            {fillings.length ? (
              <div className="chips">{fillings.map((item) => option(item, item.id === fillingId, () => setFillingId(item.id)))}</div>
            ) : (
              <p className="sub small">Nenhuma variação com correspondência confirmada está disponível para esta massa.</p>
            )}
          </div>
        )}

        {base && filling && preparations.length > 0 && (
          <div>
            <div className="parthead"><span className="partnum">3</span><h3>Preparos e componentes vinculados</h3></div>
            <div className="chips">
              {preparations.map(({ component, recipe }) => (
                <Link key={component.id} href={`/receitas/${recipe.slug}`} className="pill gold" style={{ padding: '8px 12px', fontSize: 13 }}>
                  {component.role === 'fritura' ? <Flame /> : <CookingPot />} {component.title || recipe.title}
                </Link>
              ))}
            </div>
          </div>
        )}

        {base && filling && (
          <div className="calc">
            <div className="grow">
              <div className="eyebrow">Sua combinação</div>
              <h3 style={{ marginTop: 4 }}><Sandwich size={17} style={{ verticalAlign: -3, marginRight: 6 }} />{filling.title}</h3>
              <span className="muted small">{composition}</span>
            </div>
            <div className="row">
              <Link href={`/receitas/${filling.slug}`} className="btn outline sm">Abrir ficha</Link>
              {user && access.has_access && (
                <button type="button" className="btn dark sm" onClick={() => setPlanning(true)}><Sparkles /> Adicionar à ceia</button>
              )}
            </div>
          </div>
        )}
      </div>
      {planning && filling && <AddToPlanSheet recipe={filling} factor={1} onClose={() => setPlanning(false)} />}
    </section>
  );
}
