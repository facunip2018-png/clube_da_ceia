'use client';

import { useState } from 'react';
import { Save } from 'lucide-react';
import { useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { useAdminAction } from '@/components/admin';
import { Loading, PageHead } from '@/components/ui';
import type { Challenge, Collection } from '@/lib/types';

function CollectionRow({ collection, count }: { collection: Collection; count: number }) {
  const { store } = useSession();
  const act = useAdminAction();
  const [name, setName] = useState(collection.name);
  const [description, setDescription] = useState(collection.description ?? '');
  const dirty = name !== collection.name || description !== (collection.description ?? '');
  return (
    <tr>
      <td style={{ minWidth: 200 }}><input className="field" aria-label="Nome da coleção" value={name} onChange={(e) => setName(e.target.value)} /></td>
      <td style={{ minWidth: 300 }}><input className="field" aria-label="Descrição" value={description} onChange={(e) => setDescription(e.target.value)} /></td>
      <td>{count}</td>
      <td>
        <label className="row" style={{ cursor: 'pointer' }}>
          <input type="checkbox" className="check" checked={collection.is_visible} onChange={() => act(() => store.update('collections', { id: collection.id }, { is_visible: !collection.is_visible }), { tables: ['collections', 'admin_audit_logs'], success: collection.is_visible ? 'Coleção ocultada' : 'Coleção visível' })} />
          {collection.is_visible ? 'Visível' : 'Oculta'}
        </label>
      </td>
      <td>
        {dirty && (
          <button type="button" className="btn dark sm" onClick={() => act(() => store.update('collections', { id: collection.id }, { name: name.trim() || collection.name, description: description.trim() || null }), { tables: ['collections', 'admin_audit_logs'], success: 'Coleção salva' })}>
            <Save /> Salvar
          </button>
        )}
      </td>
    </tr>
  );
}

function ChallengeRow({ challenge }: { challenge: Challenge }) {
  const { store } = useSession();
  const act = useAdminAction();
  const [points, setPoints] = useState(String(challenge.points));
  const dirty = points !== String(challenge.points);
  return (
    <tr>
      <td><span className="strong">{challenge.title}</span><br /><span className="muted small">{challenge.description}</span></td>
      <td>{challenge.badge_name ?? '—'}</td>
      <td style={{ width: 110 }}><input className="field" inputMode="numeric" aria-label="Pontos" value={points} onChange={(e) => setPoints(e.target.value)} /></td>
      <td>
        <label className="row" style={{ cursor: 'pointer' }}>
          <input type="checkbox" className="check" checked={challenge.is_active} onChange={() => act(() => store.update('challenges', { id: challenge.id }, { is_active: !challenge.is_active }), { tables: ['challenges', 'admin_audit_logs'], success: challenge.is_active ? 'Desafio desativado' : 'Desafio ativado' })} />
          {challenge.is_active ? 'Ativo' : 'Inativo'}
        </label>
      </td>
      <td>
        {dirty && (
          <button type="button" className="btn dark sm" onClick={() => act(async () => {
            const value = Math.round(Number(points));
            if (!Number.isFinite(value) || value < 0 || value > 1000) throw new Error('Pontos entre 0 e 1000.');
            await store.update('challenges', { id: challenge.id }, { points: value });
          }, { tables: ['challenges', 'admin_audit_logs'], success: 'Desafio salvo' })}>
            <Save /> Salvar
          </button>
        )}
      </td>
    </tr>
  );
}

export default function AdminCatalog() {
  const { rows: collections } = useTable('collections', { order: [['position', 'asc']] });
  const { rows: recipes } = useTable('recipes');
  const { rows: challenges } = useTable('challenges', { order: [['position', 'asc']] });
  if (!collections || !recipes || !challenges) return <Loading />;
  return (
    <>
      <PageHead eyebrow="Organização" title="Coleções e desafios." sub="Nomes, descrições e visibilidade das coleções; pontuação e ativação dos desafios da temporada." />
      <div className="tablewrap">
        <table className="table">
          <thead><tr><th>Coleção</th><th>Descrição</th><th>Itens</th><th>Visibilidade</th><th /></tr></thead>
          <tbody>{collections.map((c) => <CollectionRow key={`${c.id}:${c.updated_at}`} collection={c} count={recipes.filter((r) => r.collection_id === c.id).length} />)}</tbody>
        </table>
      </div>
      <div className="sectionhead"><div><div className="eyebrow">Gamificação</div><h2>Desafios</h2></div></div>
      <div className="tablewrap">
        <table className="table">
          <thead><tr><th>Desafio</th><th>Medalha</th><th>Pontos</th><th>Situação</th><th /></tr></thead>
          <tbody>{challenges.map((c) => <ChallengeRow key={`${c.id}:${c.updated_at}`} challenge={c} />)}</tbody>
        </table>
      </div>
    </>
  );
}
