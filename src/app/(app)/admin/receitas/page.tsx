'use client';

import { useRouter } from 'next/navigation';
import { useMemo, useState, type FormEvent } from 'react';
import { Plus } from 'lucide-react';
import { useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { useAdminAction } from '@/components/admin';
import { Loading, PageHead } from '@/components/ui';
import { normalizeText } from '@/lib/format';

function makeSlug(value: string) {
  return value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim()
    .replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

export default function AdminRecipes() {
  const router = useRouter();
  const { store } = useSession();
  const act = useAdminAction();
  const { rows: recipes } = useTable('recipes', { order: [['position', 'asc']] });
  const { rows: collections } = useTable('collections', { order: [['position', 'asc']] });
  const [collection, setCollection] = useState('all');
  const [q, setQ] = useState('');
  const [newTitle, setNewTitle] = useState('');
  const [newCollection, setNewCollection] = useState('');
  const [saving, setSaving] = useState(false);

  const list = useMemo(() => {
    const term = normalizeText(q);
    return (recipes ?? [])
      .filter((recipe) => (collection === 'all' || recipe.collection_id === collection) && (!term || normalizeText(recipe.title).includes(term)))
      .sort((a, b) => a.position - b.position);
  }, [recipes, collection, q]);

  if (!recipes || !collections) return <Loading />;

  async function createRecipe(event: FormEvent) {
    event.preventDefault();
    const title = newTitle.trim();
    const collectionId = newCollection || collections[0]?.id;
    const baseSlug = makeSlug(title);
    if (!title || !collectionId || !baseSlug) return;
    const used = new Set(recipes.map((recipe) => recipe.slug));
    let slug = baseSlug;
    let suffix = 2;
    while (used.has(slug)) slug = `${baseSlug}-${suffix++}`;
    setSaving(true);
    const created = await act(
      () => store.insert('recipes', {
        slug, collection_id: collectionId, source_document_id: null, kind: 'recipe',
        component_role: null, flavor: null, title, original_title: null,
        original_language: 'pt-BR', translation_status: 'not_needed', description: null,
        cover_image: null, difficulty: null, yield_quantity: null, yield_unit: null,
        yield_unit_plural: null, yield_detail: null, yield_text: null, servings: null,
        prep_minutes: null, cook_minutes: null, bake_minutes: null, chill_minutes: null,
        rest_minutes: null, chill_is_minimum: false, measure_note: null,
        source_page_start: null, source_page_end: null, source_pages_extra: [],
        page_ref_verified: false, content_state: 'catalogued', status: 'draft',
        position: recipes.length + 1, is_featured: false, reviewed_by: null,
        reviewed_at: null, published_at: null,
      }),
      { tables: ['recipes', 'admin_audit_logs'], success: 'Receita criada. Agora você pode completar a ficha.' },
    );
    setSaving(false);
    if (created) {
      const refreshed = await store.list('recipes', { eq: { slug } });
      setNewTitle('');
      if (refreshed[0]) router.push(`/admin/receitas/${refreshed[0].id}`);
    }
  }

  return (
    <>
      <PageHead eyebrow="Biblioteca" title="Receitas." sub="Cadastre uma receita, organize por categoria e complete ingredientes e preparo na ficha." />
      <form className="panel" onSubmit={createRecipe} style={{ marginBottom: 18 }}>
        <div className="eyebrow">Nova receita</div>
        <h2 style={{ margin: '6px 0 14px' }}>Adicionar receita</h2>
        <div className="toolbar">
          <input className="field" value={newTitle} onChange={(e) => setNewTitle(e.target.value)} placeholder="Nome da receita" aria-label="Nome da receita" required />
          <select className="select" value={newCollection || collections[0]?.id || ''} onChange={(e) => setNewCollection(e.target.value)} aria-label="Categoria" required>
            {collections.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}
          </select>
          <button className="btn dark" type="submit" disabled={saving || !newTitle.trim() || !collections.length}><Plus /> {saving ? 'Criando…' : 'Criar receita'}</button>
        </div>
        <p className="muted small">A receita começa como rascunho e só aparece para assinantes quando tiver conteúdo completo e for publicada.</p>
      </form>
      <div className="toolbar">
        <input className="field" type="search" placeholder="Buscar receita pelo nome…" aria-label="Buscar receita" value={q} onChange={(e) => setQ(e.target.value)} />
        <select className="select" value={collection} onChange={(e) => setCollection(e.target.value)} aria-label="Filtrar categoria">
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
