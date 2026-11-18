'use client';

import Link from 'next/link';
import { useParams } from 'next/navigation';
import { useMemo, useState } from 'react';
import { FileText, Hourglass, Inbox, SearchX } from 'lucide-react';
import { useCatalog, useFavoriteIds, useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { RecipeCard, countLabel } from '@/components/cards';
import { RabanadaBuilder } from '@/components/rabanada-builder';
import { CardSkeletons, Cover, Empty, ErrorState, Notice, usePageTitle } from '@/components/ui';
import { normalizeText } from '@/lib/format';
import { STATUS_LABELS } from '@/lib/recipe-view';
import type { RecipeStatus } from '@/lib/types';

const FILE_STATUS: Record<string, string> = { not_provided: 'PDF não enviado', awaiting_upload: 'PDF aguardando envio', received: 'PDF recebido', stored: 'PDF no cofre' };
const PERMISSION: Record<string, string> = { unknown: 'permissão a confirmar', confirmed: 'permissão confirmada', restricted: 'uso restrito', denied: 'uso negado' };

export default function CollectionPage() {
  const { slug } = useParams<{ slug: string }>();
  const { access, user } = useSession();
  const { summaries, loading, error } = useCatalog();
  const favorites = useFavoriteIds();
  const summary = summaries.find((s) => s.collection.slug === slug);
  const collection = summary?.collection;
  usePageTitle(collection?.name ?? 'Coleção');

  const [q, setQ] = useState('');
  const [sort, setSort] = useState<'original' | 'az'>('original');
  const [status, setStatus] = useState<RecipeStatus | 'all'>('all');
  const { rows: documents } = useTable('source_documents', access.is_admin && collection ? { eq: { collection_id: collection.id } } : null);
  const isBuilder = collection?.experience === 'builder';
  const recipeIds = useMemo(() => (summary?.recipes ?? []).map((r) => r.id), [summary]);
  const compatibilityQuery = isBuilder && user && access.has_access && recipeIds.length
    ? {
        in: { recipe_id: recipeIds },
        ...(access.is_admin ? {} : { eq: { verified: true } }),
      }
    : null;
  const { rows: compatibilities } = useTable('recipe_compatibilities', compatibilityQuery);

  const recipes = useMemo(() => {
    const term = normalizeText(q);
    const list = (summary?.recipes ?? []).filter((r) => (status === 'all' || r.status === status) && (!term || normalizeText(r.title).includes(term)));
    return sort === 'az' ? [...list].sort((a, b) => a.title.localeCompare(b.title, 'pt-BR')) : list;
  }, [summary, q, sort, status]);

  if (error) return <ErrorState error={error} />;
  if (loading) return <div className="recipegrid"><CardSkeletons count={8} /></div>;
  if (!summary || !collection) {
    return (
      <Empty icon={SearchX} title="Coleção não encontrada" action={<Link href="/colecoes" className="btn dark">Ver todas as coleções</Link>}>
        Esta coleção não existe ou não está disponível.
      </Empty>
    );
  }

  const all = summary.recipes;
  const published = all.filter((r) => r.status === 'published');
  const inPreparation = summary.stat?.in_preparation ?? 0;
  const statuses = [...new Set(all.map((r) => r.status))];

  return (
    <>
      <div className="hero" style={{ minHeight: 230, marginBottom: 22 }}>
        <Cover src={collection.cover_image} alt="" sizes="(max-width: 900px) 100vw, 80vw" className="hero-img" priority />
        <div className="hero-copy">
          <Link href="/colecoes" className="textbtn" style={{ color: '#e2c987' }}>← Todas as coleções</Link>
          <div className="eyebrow" style={{ marginTop: 10 }}>Coleção</div>
          <h1 style={{ margin: '8px 0' }}>{collection.name}</h1>
          {collection.description && <p>{collection.description}</p>}
          <div className="row" style={{ marginTop: 14 }}>
            <span className="pill onphoto">{published.length ? countLabel(published) : inPreparation ? 'Em curadoria' : 'Em breve'}</span>
            {access.is_admin && <span className="pill gold">{all.length} cadastrados · {published.length} no ar</span>}
          </div>
        </div>
      </div>

      {access.is_admin && (
        <div className="stack" style={{ marginBottom: 18 }}>
          {collection.admin_notice && <Notice tone="soft"><b>Nota da curadoria (só administradores veem):</b> {collection.admin_notice}</Notice>}
          {documents && documents.length > 0 && (
            <div className="row">
              {documents.map((d) => (
                <Link key={d.id} href="/admin/documentos" className={`pill ${d.file_status === 'not_provided' ? 'warn' : 'ok'}`} style={{ padding: '7px 12px' }}>
                  <FileText /> {d.title} · {FILE_STATUS[d.file_status]} · {PERMISSION[d.commercial_permission]}
                </Link>
              ))}
            </div>
          )}
        </div>
      )}

      {isBuilder && all.length > 0 && <RabanadaBuilder recipes={all} compatibilities={compatibilities ?? []} />}

      {all.length > 0 ? (
        <>
          <div className="toolbar">
            <input className="field" type="search" placeholder="Buscar nesta coleção…" aria-label="Buscar nesta coleção" value={q} onChange={(e) => setQ(e.target.value)} />
            <select className="select" value={sort} onChange={(e) => setSort(e.target.value as 'original' | 'az')} aria-label="Ordenação">
              <option value="original">Ordem do material</option>
              <option value="az">Ordem alfabética</option>
            </select>
          </div>
          {access.is_admin && statuses.length > 1 && (
            <div className="chips scroll" style={{ marginBottom: 14 }}>
              <button type="button" className={`filter ${status === 'all' ? 'active' : ''}`} onClick={() => setStatus('all')}>Todas ({all.length})</button>
              {statuses.map((s) => (
                <button key={s} type="button" className={`filter ${status === s ? 'active' : ''}`} onClick={() => setStatus(s)}>
                  {STATUS_LABELS[s]} ({all.filter((r) => r.status === s).length})
                </button>
              ))}
            </div>
          )}
          {recipes.length ? (
            <div className="recipegrid">
              {recipes.map((recipe) => (
                <RecipeCard key={recipe.id} recipe={recipe} collection={collection} favorite={favorites.has(recipe.id)} showStatus={access.is_admin} hideCollection />
              ))}
            </div>
          ) : (
            <Empty icon={SearchX} title="Nada encontrado">Nenhuma receita desta coleção corresponde à busca.</Empty>
          )}
          {!access.is_admin && inPreparation > 0 && (
            <div style={{ marginTop: 18 }}>
              <Notice>Mais {inPreparation} {inPreparation === 1 ? 'preparação desta coleção está' : 'preparações desta coleção estão'} em curadoria e {inPreparation === 1 ? 'será publicada' : 'serão publicadas'} após a revisão.</Notice>
            </div>
          )}
        </>
      ) : inPreparation > 0 ? (
        <Empty icon={Hourglass} title="Coleção em curadoria">
          {inPreparation} {inPreparation === 1 ? 'preparação está sendo estruturada' : 'preparações estão sendo estruturadas'} a partir do material original e {inPreparation === 1 ? 'passa' : 'passam'} por revisão antes de {inPreparation === 1 ? 'ser publicada' : 'serem publicadas'}. Não exibimos ingredientes ou instruções que não tenham sido conferidos.
        </Empty>
      ) : (
        <Empty icon={Inbox} title="Conteúdo em breve">
          Esta coleção já está preparada no Clube e será preenchida assim que o material de origem for recebido e revisado.
        </Empty>
      )}
    </>
  );
}
