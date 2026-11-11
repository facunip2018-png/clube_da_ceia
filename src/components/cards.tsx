'use client';

import Link from 'next/link';
import { ArrowRight, Clock, Heart, Lock, UtensilsCrossed } from 'lucide-react';
import type { Collection, Recipe, RecipeStatus } from '@/lib/types';
import { STATUS_LABELS, knownTimes } from '@/lib/recipe-view';
import { formatMinutes } from '@/lib/format';
import { useSession } from '@/data/session';
import { toggleFavorite } from '@/data/actions';
import type { CollectionSummary } from '@/data/hooks';
import { Photo } from './ui';
import { useToast } from './toast';

const STATUS_TONE: Record<RecipeStatus, string> = {
  draft: 'muted', review: 'warn', approved: 'gold', published: 'ok', pending_permission: 'danger', archived: 'muted',
};

export function StatusPill({ status }: { status: RecipeStatus }) {
  return <span className={`pill ${STATUS_TONE[status]}`}>{STATUS_LABELS[status]}</span>;
}

const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;

/** Contagem real, distinguindo receitas completas, componentes e variações. */
export function countLabel(recipes: Pick<Recipe, 'kind'>[]): string {
  const count = (kind: Recipe['kind']) => recipes.filter((r) => r.kind === kind).length;
  const parts = [
    count('recipe') ? plural(count('recipe'), 'receita', 'receitas') : null,
    count('component') ? plural(count('component'), 'componente', 'componentes') : null,
    count('variation') ? plural(count('variation'), 'variação', 'variações') : null,
  ].filter(Boolean);
  return parts.join(' · ');
}

export function CollectionCard({ summary, priority }: { summary: CollectionSummary; priority?: boolean }) {
  const { access } = useSession();
  const { collection, recipes, stat } = summary;
  const published = recipes.filter((r) => r.status === 'published');
  const inPreparation = stat?.in_preparation ?? 0;
  const state = published.length ? 'open' : inPreparation ? 'curation' : 'waiting';
  const meta = access.is_admin
    ? `${plural(recipes.length, 'item', 'itens')} · ${published.length} no ar`
    : state === 'open'
      ? countLabel(published)
      : state === 'curation'
        ? 'Em preparação'
        : 'Em breve';
  return (
    <article className="collection">
      <Photo src={collection.cover_image} alt="" sizes="(max-width: 600px) 50vw, (max-width: 1100px) 50vw, 33vw" priority={priority}>
        <div className="tl">
          {state === 'open' && <span className="pill onphoto">{countLabel(published)}</span>}
          {state === 'curation' && <span className="pill gold">Em curadoria</span>}
          {state === 'waiting' && <span className="pill onphoto">Em breve</span>}
        </div>
      </Photo>
      <div className="collection-body">
        <h3>
          <Link href={`/colecoes/${collection.slug}`} className="cardlink">{collection.name}</Link>
        </h3>
        {collection.description && <p className="sub small">{collection.description}</p>}
        <div className="collection-meta">
          <span>{meta}</span>
          <span className="go"><span>Abrir</span> <ArrowRight /></span>
        </div>
      </div>
    </article>
  );
}

export function RecipeCard({ recipe, collection, favorite, showStatus, hideCollection }: { recipe: Recipe; collection?: Collection | null; favorite?: boolean; showStatus?: boolean; hideCollection?: boolean }) {
  const { user, store, access } = useSession();
  const { toast, fail } = useToast();
  const time = knownTimes(recipe)[0];
  const cover = recipe.cover_image ?? collection?.cover_image ?? null;

  async function onFavorite() {
    try {
      const now = await toggleFavorite(store, recipe.id, Boolean(favorite));
      toast(now ? 'Salva nas suas favoritas' : 'Removida das favoritas');
    } catch (error) {
      fail(error);
    }
  }

  return (
    <article className="recipe">
      <Photo src={cover} alt="" sizes="(max-width: 900px) 50vw, (max-width: 1250px) 33vw, 25vw" className={recipe.cover_image ? '' : 'stub'}>
        <div className="tl">
          {showStatus && <StatusPill status={recipe.status} />}
          {recipe.kind !== 'recipe' && <span className="pill onphoto">{recipe.kind === 'component' ? 'Componente' : 'Variação'}</span>}
        </div>
        {user && recipe.status === 'published' && (
          <div className="tr">
            <button type="button" className={`favbtn ${favorite ? 'on' : ''}`} onClick={onFavorite} aria-pressed={Boolean(favorite)} aria-label={favorite ? 'Remover das favoritas' : 'Salvar nas favoritas'}>
              <Heart />
            </button>
          </div>
        )}
      </Photo>
      <div className="rbody">
        <h3>
          <Link href={`/receitas/${recipe.slug}`} className="cardlink">{recipe.title}</Link>
        </h3>
        {collection && !hideCollection && <span className="muted small">{collection.name}</span>}
        <div className="rmeta">
          {recipe.content_state === 'catalogued' ? (
            <span><UtensilsCrossed /> Ficha aguardando PDF</span>
          ) : time ? (
            <span><Clock /> {time.label} {time.minimum ? 'mín. ' : ''}{formatMinutes(time.minutes)}</span>
          ) : (
            <span>{recipe.yield_text ?? 'Ficha completa'}</span>
          )}
          {!access.has_access && <span title="Conteúdo da temporada"><Lock /></span>}
        </div>
      </div>
    </article>
  );
}
