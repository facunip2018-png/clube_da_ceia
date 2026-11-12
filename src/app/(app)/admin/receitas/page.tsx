'use client';

import { useRouter } from 'next/navigation';
import { useMemo, useState } from 'react';
import { useTable } from '@/data/hooks';
import { Loading, PageHead } from '@/components/ui';
import { normalizeText } from '@/lib/format';

export default function AdminRecipes() {
  const router = useRouter();
  const { rows: recipes } = useTable('recipes', { order: [['position', 'asc']] });
  const { rows: collections } = useTable('collections', { order: [['position', 'asc']] });
  const [collection, setCollection] = useState('all');
  const [q, setQ] = useState('');

  const list = useMemo(() => {
    const term = normalizeText(q);
    return (recipes ?? [])
      .filter((recipe) => (collection === 'all' || recipe.collection_id === collection) && (!term || normalizeText(recipe.title).includes(term)))
      .sort((a, b) => a.position - b.position);
  }, [recipes, collection, q]);

  if (!recipes || !collections) return <Loading />;

  return (
    <>
      <PageHead eyebrow="Biblioteca" title="Receitas." sub="Todas as receitas organizadas por categoria. Abra uma ficha para consultar ou editar os detalhes." />
      <div className="toolbar">
        <input className="field" type="search" placeholder="Buscar receita pelo nome…" aria-label="Buscar receita" value={q} onChange={(e) => setQ(e.target.value)} />
        <select className="select" value={collection} onChange={(e) => setCollection(e.target.value)} aria-label="Categoria">
          <option value="all">Todas as categorias</option>
          {collections.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}
        </select>
      </div>
      <p className="muted small" style={{ marginBottom: 10 }}>{list.length} receita(s)</p>
      <div className="tablewrap">
        <table className="table">
          <thead><tr><th>Receita</th><th>Categoria</th><th>Ficha</th><th>Disponibilidade</th></tr></thead>
          <tbody>
            {list.map((recipe) => (
              <tr key={recipe.id} className="clickable" onClick={() => router.push(`/admin/receitas/${recipe.id}`)} tabIndex={0} onKeyDown={(e) => e.key === 'Enter' && router.push(`/admin/receitas/${recipe.id}`)}>
                <td className="strong">{recipe.title}</td>
                <td>{collections.find((item) => item.id === recipe.collection_id)?.name ?? 'Sem categoria'}</td>
                <td>{recipe.content_state === 'structured' ? <span className="pill ok">Completa</span> : <span className="pill muted">Aguardando conteúdo</span>}</td>
                <td>{recipe.status === 'published' ? <span className="pill ok">No ar</span> : recipe.status === 'archived' ? <span className="pill muted">Arquivada</span> : <span className="pill warn">Não publicada</span>}</td>
              </tr>
            ))}
            {!list.length && <tr><td colSpan={4} className="muted center">Nenhuma receita encontrada.</td></tr>}
          </tbody>
        </table>
      </div>
    </>
  );
}
