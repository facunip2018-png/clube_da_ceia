'use client';

import { useRouter } from 'next/navigation';
import { useMemo, useState } from 'react';
import { useTable } from '@/data/hooks';
import { StatusPill } from '@/components/cards';
import { Loading, PageHead } from '@/components/ui';
import { normalizeText, pageRange } from '@/lib/format';
import { STATUS_LABELS } from '@/lib/recipe-view';
import type { RecipeStatus } from '@/lib/types';

const KIND: Record<string, string> = { recipe: 'Receita', component: 'Componente', variation: 'Variação' };

export default function AdminRecipes() {
  const router = useRouter();
  const { rows: recipes } = useTable('recipes', { order: [['position', 'asc']] });
  const { rows: collections } = useTable('collections', { order: [['position', 'asc']] });
  const { rows: flags } = useTable('review_flags', { eq: { resolved_at: null } });
  const [collection, setCollection] = useState('all');
  const [status, setStatus] = useState<RecipeStatus | 'all'>('all');
  const [onlyStructured, setOnlyStructured] = useState(false);
  const [q, setQ] = useState('');

  const list = useMemo(() => {
    const term = normalizeText(q);
    const order = new Map((collections ?? []).map((c, i) => [c.id, i]));
    return (recipes ?? [])
      .filter((r) => (collection === 'all' || r.collection_id === collection) && (status === 'all' || r.status === status) && (!onlyStructured || r.content_state === 'structured') && (!term || normalizeText(r.title).includes(term)))
      .sort((a, b) => (order.get(a.collection_id) ?? 0) - (order.get(b.collection_id) ?? 0) || a.position - b.position);
  }, [recipes, collections, collection, status, onlyStructured, q]);

  if (!recipes || !collections) return <Loading />;
  const pending = (id: string) => (flags ?? []).filter((f) => f.recipe_id === id && f.severity !== 'info').length;

  return (
    <>
      <PageHead eyebrow="Curadoria" title="Receitas." sub="Cada item nasce como rascunho. Só entra no ar depois de revisado, aprovado e com a permissão comercial do material confirmada." />
      <div className="toolbar">
        <input className="field" type="search" placeholder="Buscar pelo título…" aria-label="Buscar pelo título" value={q} onChange={(e) => setQ(e.target.value)} />
        <select className="select" value={collection} onChange={(e) => setCollection(e.target.value)} aria-label="Coleção">
          <option value="all">Todas as coleções</option>
          {collections.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>
        <select className="select" value={status} onChange={(e) => setStatus(e.target.value as RecipeStatus | 'all')} aria-label="Situação">
          <option value="all">Todas as situações</option>
          {(Object.keys(STATUS_LABELS) as RecipeStatus[]).map((s) => <option key={s} value={s}>{STATUS_LABELS[s]}</option>)}
        </select>
        <button type="button" className={`filter ${onlyStructured ? 'active' : ''}`} onClick={() => setOnlyStructured(!onlyStructured)} aria-pressed={onlyStructured}>Só com ficha</button>
      </div>
      <p className="muted small" style={{ marginBottom: 10 }}>{list.length} de {recipes.length} itens</p>
      <div className="tablewrap">
        <table className="table">
          <thead><tr><th>Título</th><th>Coleção</th><th>Tipo</th><th>Ficha</th><th>Situação</th><th>Pendências</th><th>Origem</th></tr></thead>
          <tbody>
            {list.map((recipe) => (
              <tr key={recipe.id} className="clickable" onClick={() => router.push(`/admin/receitas/${recipe.id}`)} tabIndex={0} onKeyDown={(e) => e.key === 'Enter' && router.push(`/admin/receitas/${recipe.id}`)}>
                <td className="strong">{recipe.title}{recipe.translation_status === 'pending' && <span className="pill warn" style={{ marginLeft: 8 }}>tradução</span>}</td>
                <td>{collections.find((c) => c.id === recipe.collection_id)?.name}</td>
                <td>{KIND[recipe.kind]}</td>
                <td>{recipe.content_state === 'structured' ? <span className="pill ok">Estruturada</span> : <span className="pill muted">Aguardando PDF</span>}</td>
                <td><StatusPill status={recipe.status} /></td>
                <td>{pending(recipe.id) > 0 ? <span className="pill warn">{pending(recipe.id)}</span> : '—'}</td>
                <td className="muted">{pageRange(recipe.source_page_start, recipe.source_page_end) ?? '—'}{recipe.source_page_start && !recipe.page_ref_verified ? ' (a conferir)' : ''}</td>
              </tr>
            ))}
            {!list.length && <tr><td colSpan={7} className="muted center">Nenhum item com esses filtros.</td></tr>}
          </tbody>
        </table>
      </div>
    </>
  );
}
