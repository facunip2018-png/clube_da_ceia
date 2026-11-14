'use client';

import Link from 'next/link';
import { useMemo, useState } from 'react';
import { Check, CookingPot, Flame, Sandwich, Sparkles } from 'lucide-react';
import type { Recipe, RecipeCompatibility } from '@/lib/types';
import { visibleRecipeCompatibilities } from '@/lib/recipe-compatibility';
import { Notice } from './ui';
import { AddToPlanSheet } from './add-to-plan';
import { useSession } from '@/data/session';

/**
 * MONTE SUA RABANADA — combina base, preparos e recheio.
 * Só oferece combinações registradas a partir do material original (recipe_compatibilities).
 */
export function RabanadaBuilder({ recipes, compatibilities }: { recipes: Recipe[]; compatibilities: RecipeCompatibility[] }) {
  const { access, user } = useSession();
  const bases = useMemo(() => recipes.filter((r) => r.component_role === 'base'), [recipes]);
  const shared = useMemo(() => recipes.filter((r) => r.kind === 'component' && r.component_role !== 'base' && r.component_role !== 'finalizacao'), [recipes]);
  const [baseId, setBaseId] = useState<string | null>(null);
  const [fillingId, setFillingId] = useState<string | null>(null);
  const [finishId, setFinishId] = useState<string | null>(null);
  const [planning, setPlanning] = useState(false);

  const base = bases.find((b) => b.id === baseId) ?? null;
  const visibleCompatibilities = useMemo(
    () => visibleRecipeCompatibilities(compatibilities, access.is_admin),
    [compatibilities, access.is_admin],
  );
  const compatible = (relation: string) => {
    if (!base) return [];
    const ids = new Set(visibleCompatibilities.filter((c) => c.recipe_id === base.id && c.relation === relation).map((c) => c.compatible_recipe_id));
    return recipes.filter((r) => ids.has(r.id));
  };
  const fillings = compatible('recheio');
  const finishes = compatible('finalizacao');
  const filling = fillings.find((f) => f.id === fillingId) ?? null;
  const unverified = compatibilities.some((c) => !c.verified);

  if (!bases.length) return null;

  const option = (recipe: Recipe, selected: boolean, onSelect: () => void, hint?: string) => (
    <button key={recipe.id} type="button" className={`filter ${selected ? 'active' : ''}`} onClick={onSelect} aria-pressed={selected} style={{ whiteSpace: 'normal', textAlign: 'left', borderRadius: 14 }}>
      {selected && <Check size={14} style={{ marginRight: 6, verticalAlign: -2 }} />}
      {recipe.title}
      {hint && <span style={{ opacity: 0.7 }}> · {hint}</span>}
    </button>
  );

  return (
    <section className="panel" style={{ marginBottom: 22, background: 'linear-gradient(160deg,#fffdf6,#fff)' }}>
      <div className="eyebrow">✦ Experiência interativa</div>
      <h2 style={{ margin: '6px 0 4px' }}>Monte sua rabanada</h2>
      <p className="sub">Escolha o pão e veja os preparos da base. Recheios e finalizações só aparecem após confirmação no material original.</p>

      {access.is_admin && unverified && (
        <div style={{ marginTop: 14 }}>
          <Notice>
            <b>Prévia para a administração.</b> As combinações abaixo foram inferidas dos títulos (doce com doce, salgado com salgado) e ainda precisam ser conferidas no PDF antes de o montador ser publicado.
          </Notice>
        </div>
      )}

      <div className="stack" style={{ marginTop: 18 }}>
        <div>
          <div className="parthead"><span className="partnum">1</span><h3>Escolha o pão</h3></div>
          <div className="chips">
            {bases.map((b) => option(b, b.id === baseId, () => { setBaseId(b.id); setFillingId(null); setFinishId(null); }, b.flavor ?? undefined))}
          </div>
        </div>

        {base && shared.length > 0 && (
          <div>
            <div className="parthead"><span className="partnum">2</span><h3>Preparos da base</h3></div>
            <div className="chips">
              {shared.map((s) => (
                <Link key={s.id} href={`/receitas/${s.slug}`} className="pill gold" style={{ padding: '8px 12px', fontSize: 13 }}>
                  {s.component_role === 'fritura' ? <Flame /> : <CookingPot />} {s.title}
                </Link>
              ))}
            </div>
          </div>
        )}

        {base && (
          <div>
            <div className="parthead"><span className="partnum">{shared.length ? 3 : 2}</span><h3>Escolha o recheio</h3></div>
            {fillings.length ? (
              <div className="chips">{fillings.map((f) => option(f, f.id === fillingId, () => setFillingId(f.id)))}</div>
            ) : (
              <p className="sub small">Nenhuma combinação confirmada para esta base no material.</p>
            )}
          </div>
        )}

        {base && filling && finishes.length > 0 && (
          <div>
            <div className="parthead"><span className="partnum">{shared.length ? 4 : 3}</span><h3>Finalização</h3></div>
            <div className="chips">{finishes.map((f) => option(f, f.id === finishId, () => setFinishId(f.id === finishId ? null : f.id)))}</div>
          </div>
        )}

        {base && filling && (
          <div className="calc">
            <div className="grow">
              <div className="eyebrow">Sua combinação</div>
              <h3 style={{ marginTop: 4 }}><Sandwich size={17} style={{ verticalAlign: -3, marginRight: 6 }} />{filling.title}</h3>
              <span className="muted small">
                {[base.title, ...shared.map((s) => s.title), finishes.find((f) => f.id === finishId)?.title].filter(Boolean).join(' + ')}
              </span>
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
