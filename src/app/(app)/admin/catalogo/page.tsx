'use client';

import { useState, type FormEvent } from 'react';
import { Plus, Save } from 'lucide-react';
import { useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { useAdminAction } from '@/components/admin';
import { Loading, PageHead } from '@/components/ui';
import type { Collection } from '@/lib/types';

function makeSlug(value: string) {
  return value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim()
    .replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

function NewCategory({ collections }: { collections: Collection[] }) {
  const { store } = useSession();
  const act = useAdminAction();
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [saving, setSaving] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    const cleanName = name.trim();
    const slug = makeSlug(cleanName);
    if (!cleanName || !slug) return;
    if (collections.some((item) => item.slug === slug)) {
      await act(async () => { throw new Error('Já existe uma categoria com esse nome.'); }, { tables: [] });
      return;
    }
    setSaving(true);
    const ok = await act(
      () => store.insert('collections', {
        slug, name: cleanName, description: description.trim() || null,
        cover_image: null, experience: 'catalog', position: Math.max(0, ...collections.map((c) => c.position)) + 1,
        is_visible: true, admin_notice: null,
      }),
      { tables: ['collections', 'admin_audit_logs'], success: 'Categoria criada e disponível no catálogo' },
    );
    if (ok) { setName(''); setDescription(''); }
    setSaving(false);
  }

  return (
    <form className="panel" onSubmit={submit} style={{ marginBottom: 18 }}>
      <div className="eyebrow">Nova categoria</div>
      <h2 style={{ margin: '6px 0 14px' }}>Adicionar uma categoria</h2>
      <div className="formgrid">
        <div className="group">
          <label htmlFor="category-name">Nome da categoria</label>
          <input id="category-name" className="field" value={name} onChange={(e) => setName(e.target.value)} placeholder="Ex.: Rabanadas" required />
        </div>
        <div className="group">
          <label htmlFor="category-description">Descrição (opcional)</label>
          <input id="category-description" className="field" value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Uma breve apresentação" />
        </div>
        <div className="group full">
          <button className="btn dark" type="submit" disabled={saving || !name.trim()}><Plus /> {saving ? 'Criando…' : 'Criar categoria'}</button>
        </div>
      </div>
      <p className="muted small">A categoria será criada como visível. Depois, as receitas poderão ser vinculadas a ela.</p>
    </form>
  );
}

function CategoryRow({ collection, count }: { collection: Collection; count: number }) {
  const { store } = useSession();
  const act = useAdminAction();
  const [name, setName] = useState(collection.name);
  const [description, setDescription] = useState(collection.description ?? '');
  const dirty = name !== collection.name || description !== (collection.description ?? '');
  return (
    <tr>
      <td style={{ minWidth: 200 }}><input className="field" aria-label="Nome da categoria" value={name} onChange={(e) => setName(e.target.value)} /></td>
      <td style={{ minWidth: 300 }}><input className="field" aria-label="Descrição" value={description} onChange={(e) => setDescription(e.target.value)} /></td>
      <td>{count}</td>
      <td>
        <label className="row" style={{ cursor: 'pointer' }}>
          <input type="checkbox" className="check" checked={collection.is_visible} onChange={() => act(() => store.update('collections', { id: collection.id }, { is_visible: !collection.is_visible }), { tables: ['collections', 'admin_audit_logs'], success: collection.is_visible ? 'Categoria ocultada' : 'Categoria visível' })} />
          {collection.is_visible ? 'Visível' : 'Oculta'}
        </label>
      </td>
      <td>
        {dirty && <button type="button" className="btn dark sm" onClick={() => act(() => store.update('collections', { id: collection.id }, { name: name.trim() || collection.name, description: description.trim() || null }), { tables: ['collections', 'admin_audit_logs'], success: 'Categoria salva' })}><Save /> Salvar</button>}
      </td>
    </tr>
  );
}

export default function AdminCatalog() {
  const { rows: collections } = useTable('collections', { order: [['position', 'asc']] });
  const { rows: recipes } = useTable('recipes');
  if (!collections || !recipes) return <Loading />;
  return (
    <>
      <PageHead eyebrow="Organização da biblioteca" title="Categorias de receitas." sub="Crie categorias como Panetones, Manjares, Tortas e Rabanadas. Você poderá acrescentar novas categorias sempre que precisar." />
      <NewCategory collections={collections} />
      <div className="tablewrap">
        <table className="table">
          <thead><tr><th>Categoria</th><th>Descrição</th><th>Receitas</th><th>Visibilidade</th><th /></tr></thead>
          <tbody>{collections.map((c) => <CategoryRow key={`${c.id}:${c.updated_at}`} collection={c} count={recipes.filter((r) => r.collection_id === c.id).length} />)}</tbody>
        </table>
      </div>
    </>
  );
}
