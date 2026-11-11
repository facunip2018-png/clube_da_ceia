'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { Suspense, useMemo } from 'react';
import { SearchX } from 'lucide-react';
import { useCatalog, useFavoriteIds } from '@/data/hooks';
import { useSession } from '@/data/session';
import { CollectionCard, RecipeCard, countLabel } from '@/components/cards';
import { CardSkeletons, Empty, ErrorState, Notice, PageHead, usePageTitle } from '@/components/ui';
import { normalizeText } from '@/lib/format';

function Collections() {
  usePageTitle('Coleções e receitas');
  const router = useRouter();
  const params = useSearchParams();
  const q = params.get('q') ?? '';
  const { access } = useSession();
  const { summaries, recipes, collections, stats, loading, error } = useCatalog();
  const favorites = useFavoriteIds();
  const published = recipes.filter((r) => r.status === 'published');
  const inPreparation = stats.reduce((sum, s) => sum + s.in_preparation, 0);
  const waiting = summaries.filter((s) => !s.recipes.length && !(s.stat?.in_preparation ?? 0));

  const results = useMemo(() => {
    const term = normalizeText(q);
    if (!term) return null;
    return recipes.filter((r) => normalizeText(`${r.title} ${r.description ?? ''}`).includes(term));
  }, [q, recipes]);

  return (
    <>
      <PageHead eyebrow="Caderno de receitas" title="Escolha sua coleção." sub="Navegue por categoria e descubra as preparações de cada material.">
        {!loading && (
          <span className="pill">
            {published.length ? countLabel(published).toUpperCase() : 'CATÁLOGO EM CURADORIA'}
          </span>
        )}
      </PageHead>

      <div className="toolbar">
        <input
          className="field"
          type="search"
          placeholder="Buscar uma receita…"
          aria-label="Buscar uma receita"
          defaultValue={q}
          key={q}
          onKeyDown={(event) => {
            if (event.key === 'Enter') {
              const value = event.currentTarget.value.trim();
              router.replace(value ? `/colecoes?q=${encodeURIComponent(value)}` : '/colecoes');
            }
          }}
        />
        {q && <button type="button" className="btn outline sm" onClick={() => router.replace('/colecoes')}>Limpar busca</button>}
      </div>

      {error ? (
        <ErrorState error={error} />
      ) : results ? (
        results.length ? (
          <>
            <p className="sub" style={{ marginBottom: 14 }}>{results.length} resultado{results.length > 1 ? 's' : ''} para “{q}”</p>
            <div className="recipegrid">
              {results.map((recipe) => (
                <RecipeCard key={recipe.id} recipe={recipe} collection={collections.find((c) => c.id === recipe.collection_id)} favorite={favorites.has(recipe.id)} showStatus={access.is_admin} />
              ))}
            </div>
          </>
        ) : (
          <Empty icon={SearchX} title="Nada encontrado">Não há receitas disponíveis com “{q}”. Tente outro termo ou navegue pelas coleções.</Empty>
        )
      ) : (
        <>
          <div className="collection-grid">
            {loading ? <CardSkeletons count={6} height={270} /> : summaries.map((s, i) => <CollectionCard key={s.collection.id} summary={s} priority={i < 3} />)}
          </div>
          {!loading && (inPreparation > 0 || waiting.length > 0) && (
            <div style={{ marginTop: 20 }}>
              <Notice>
                {inPreparation > 0 && (
                  <>
                    <b>{inPreparation} {inPreparation === 1 ? 'preparação está' : 'preparações estão'} em curadoria.</b> Cada ficha é estruturada a partir do material original e revisada antes de ser publicada — nada é inventado ou completado por suposição.{' '}
                  </>
                )}
                {waiting.length > 0 && <>{waiting.map((s) => s.collection.name).join(' e ')} {waiting.length > 1 ? 'aguardam' : 'aguarda'} o envio do material de origem.</>}
              </Notice>
            </div>
          )}
        </>
      )}
    </>
  );
}

export default function CollectionsPage() {
  return (
    <Suspense>
      <Collections />
    </Suspense>
  );
}
