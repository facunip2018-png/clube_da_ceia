'use client';

import Link from 'next/link';
import { useMemo, useState } from 'react';
import { Check, Sandwich, Sparkles } from 'lucide-react';
import type { Recipe, RecipeCompatibility } from '@/lib/types';
import {
  pendingRabanadaCompatibilityCount,
  rabanadaBaseIds,
  rabanadaOptionIds,
  verifiedRabanadaCompatibilities,
} from '@/lib/rabanada-compatibility';
import { Notice } from './ui';
import { AddToPlanSheet } from './add-to-plan';
import { useSession } from '@/data/session';

/**
 * MONTE SUA RABANADA — só apresenta pares de base/recheio/finalização
 * marcados como verificados contra o documento original.
 */
export function RabanadaBuilder({ recipes, compatibilities }: { recipes: Recipe[]; compatibilities: RecipeCompatibility[] }) {
  const { access, user } = useSession();
  const verifiedCompatibilities = useMemo(
    () => verifiedRabanadaCompatibilities(compatibilities),
    [compatibilities],
  );
  const pendingCount = pendingRabanadaCompatibilityCount(compatibilities);
  const allowedBaseIds = useMemo(
    () => rabanadaBaseIds(verifiedCompatibilities),
    [verifiedCompatibilities],
  );
  const bases = useMemo(
    () => recipes.filter((recipe) => recipe.component_role === 'base' && allowedBaseIds.has(recipe.id)),
    [recipes, allowedBaseIds],
  );
  const [baseId, setBaseId] = useState<string | null>(null);
  const [fillingId, setFillingId] = useState<string | null>(null);
  const [finishId, setFinishId] = useState<string | null>(null);
  const [planning, setPlanning] = useState(false);

  const base = bases.find((item) => item.id === baseId) ?? null;
  const compatible = (relation: string) => {
    if (!base) return [];
    const ids = rabanadaOptionIds(verifiedCompatibilities, base.id, relation);
    return recipes.filter((recipe) => ids.has(recipe.id));
  };
  const fillings = compatible('recheio');
  const finishes = compatible('finalizacao');
  const filling = fillings.find((item) => item.id === fillingId) ?? null;
  const finish = finishes.find((item) => item.id === finishId) ?? null;

  // Falha fechada: se não houver pares verificados, clientes não veem o montador.
  // A administração recebe apenas um aviso, sem opções inferidas ou potencialmente erradas.
  if (!verifiedCompatibilities.length) {
    if (!access.is_admin || pendingCount === 0) return null;
    return (
      <section className="panel" style={{ marginBottom: 22 }}>
        <div className="eyebrow">✦ Experiência interativa</div>
        <h2 style={{ margin: '6px 0 4px' }}>Monte sua rabanada</h2>
        <Notice>
          <b>Montador indisponível.</b> Existem {pendingCount} combinações sem verificação da fonte original.
          Elas foram preservadas no banco, mas não são oferecidas como opções até a conferência documental.
        </Notice>
      </section>
    );
  }

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

  return (
    <section className="panel" style={{ marginBottom: 22, background: 'linear-gradient(160deg,#fffdf6,#fff)' }}>
      <div className="eyebrow">✦ Experiência interativa</div>
      <h2 style={{ margin: '6px 0 4px' }}>Monte sua rabanada</h2>
      <p className="sub">Escolha uma base e combine somente com opções verificadas no material original.</p>

      {access.is_admin && pendingCount > 0 && (
        <div style={{ marginTop: 14 }}>
          <Notice>
            <b>Prévia da administração.</b> {pendingCount} combinação(ões) ainda aguardam conferência e não aparecem no montador.
          </Notice>
        </div>
      )}

      <div className="stack" style={{ marginTop: 18 }}>
        <div>
          <div className="parthead"><span className="partnum">1</span><h3>Escolha o pão</h3></div>
          <div className="chips">
            {bases.map((item) => option(item, item.id === baseId, () => {
              setBaseId(item.id);
              setFillingId(null);
              setFinishId(null);
            }))}
          </div>
        </div>

        {base && (
          <div>
            <div className="parthead"><span className="partnum">2</span><h3>Escolha o recheio</h3></div>
            {fillings.length ? (
              <div className="chips">{fillings.map((item) => option(item, item.id === fillingId, () => setFillingId(item.id)))}</div>
            ) : (
              <p className="sub small">Nenhum recheio verificado está registrado para esta base.</p>
            )}
          </div>
        )}

        {base && filling && finishes.length > 0 && (
          <div>
            <div className="parthead"><span className="partnum">3</span><h3>Finalização</h3></div>
            <div className="chips">{finishes.map((item) => option(item, item.id === finishId, () => setFinishId(item.id === finishId ? null : item.id)))}</div>
          </div>
        )}

        {base && filling && (
          <div className="calc">
            <div className="grow">
              <div className="eyebrow">Sua combinação verificada</div>
              <h3 style={{ marginTop: 4 }}><Sandwich size={17} style={{ verticalAlign: -3, marginRight: 6 }} />{filling.title}</h3>
              <span className="muted small">{[base.title, finish?.title].filter(Boolean).join(' + ')}</span>
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
