'use client';

import { useMemo, useState } from 'react';
import { BookOpenText, Eye, EyeOff, Pencil, Plus, Save } from 'lucide-react';
import { useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { useAdminAction } from '@/components/admin';
import { Empty, Loading, PageHead, usePageTitle } from '@/components/ui';
import type { SupportMaterial } from '@/lib/types';

const KINDS: { value: SupportMaterial['kind']; label: string }[] = [
  { value: 'utensilios', label: 'Utensílios' },
  { value: 'ingredientes', label: 'Ingredientes básicos' },
  { value: 'dicas', label: 'Dicas' },
  { value: 'orientacoes', label: 'Orientações gerais' },
];

const slugify = (value: string) => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

export default function AdminSupportMaterialsPage() {
  usePageTitle('Materiais de apoio');
  const { store } = useSession();
  const act = useAdminAction();
  const { rows, loading } = useTable('support_materials', { order: [['position', 'asc'], ['title', 'asc']] });
  const { rows: documents } = useTable('source_documents', { order: [['title', 'asc']] });
  const [editing, setEditing] = useState<string | null>(null);
  const [kind, setKind] = useState<SupportMaterial['kind']>('dicas');
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [sourceDocumentId, setSourceDocumentId] = useState('');
  const [sourcePage, setSourcePage] = useState('');
  const grouped = useMemo(() => KINDS.map((k) => ({ ...k, items: (rows ?? []).filter((r) => r.kind === k.value) })), [rows]);

  function reset() {
    setEditing(null); setKind('dicas'); setTitle(''); setBody(''); setSourceDocumentId(''); setSourcePage('');
  }
  function edit(item: SupportMaterial) {
    setEditing(item.id); setKind(item.kind); setTitle(item.title); setBody(item.body);
    setSourceDocumentId(item.source_document_id ?? ''); setSourcePage(item.source_page ? String(item.source_page) : '');
  }
  async function save() {
    if (!title.trim() || !body.trim()) return;
    const slug = slugify(title);
    const payload = {
      slug, kind, title: title.trim(), body: body.trim(),
      source_document_id: sourceDocumentId || null,
      source_page: sourcePage.trim() ? Number(sourcePage) : null,
    };
    const ok = await act(
      () => editing
        ? store.update('support_materials', { id: editing }, payload)
        : store.insert('support_materials', { ...payload, position: (rows ?? []).length + 1, is_visible: true }),
      { tables: ['support_materials'], success: editing ? 'Material atualizado' : 'Material cadastrado' },
    );
    if (ok) reset();
  }

  if (loading || !documents) return <Loading />;

  return (
    <>
      <PageHead eyebrow="Conteúdo complementar" title="Materiais de apoio." sub="Cadastre uma vez e mantenha utensílios, ingredientes básicos, dicas e orientações em uma área própria, separada das receitas." />
      <section className="panel stack">
        <div className="spread">
          <h2 style={{ margin: 0 }}>{editing ? 'Editar material' : 'Adicionar material'}</h2>
          {editing && <button type="button" className="btn ghost sm" onClick={reset}>Cancelar edição</button>}
        </div>
        <div className="formgrid">
          <div className="group">
            <label htmlFor="support-kind">Tipo</label>
            <select id="support-kind" className="select" value={kind} onChange={(e) => setKind(e.target.value as SupportMaterial['kind'])}>
              {KINDS.map((k) => <option key={k.value} value={k.value}>{k.label}</option>)}
            </select>
          </div>
          <div className="group">
            <label htmlFor="support-title">Título</label>
            <input id="support-title" className="field" value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Ex.: Utensílios básicos" />
          </div>
          <div className="group">
            <label htmlFor="support-document">Material de origem (opcional)</label>
            <select id="support-document" className="select" value={sourceDocumentId} onChange={(e) => setSourceDocumentId(e.target.value)}>
              <option value="">Sem vínculo</option>
              {documents.map((d) => <option key={d.id} value={d.id}>{d.title}</option>)}
            </select>
          </div>
          <div className="group">
            <label htmlFor="support-page">Página (opcional)</label>
            <input id="support-page" className="field" inputMode="numeric" value={sourcePage} onChange={(e) => setSourcePage(e.target.value.replace(/[^0-9]/g, ''))} placeholder="Ex.: 8" />
          </div>
        </div>
        <div className="group">
          <label htmlFor="support-body">Conteúdo</label>
          <textarea id="support-body" className="field" rows={8} value={body} onChange={(e) => setBody(e.target.value)} placeholder="Cole aqui o texto do material de apoio, sem misturar com as fichas de receitas." />
        </div>
        <div className="row">
          <button type="button" className="btn dark" disabled={!title.trim() || !body.trim()} onClick={save}><Save /> {editing ? 'Salvar alterações' : 'Cadastrar material'}</button>
          {!editing && <span className="muted small">O material entra na área de apoio para assinantes após salvar.</span>}
        </div>
      </section>

      <div className="stack" style={{ marginTop: 20 }}>
        {grouped.map((group) => (
          <section className="panel stack" key={group.value}>
            <div className="spread"><h2 style={{ margin: 0 }}>{group.label}</h2><span className="pill">{group.items.length}</span></div>
            {group.items.length ? group.items.map((item) => (
              <article className="spread" key={item.id} style={{ borderTop: '1px solid var(--line)', paddingTop: 12, alignItems: 'flex-start' }}>
                <div className="grow">
                  <b>{item.title}</b>
                  <p className="muted small" style={{ whiteSpace: 'pre-wrap', margin: '5px 0' }}>{item.body.slice(0, 180)}{item.body.length > 180 ? '…' : ''}</p>
                  <span className="muted small">{item.is_visible ? 'Visível para assinantes' : 'Oculto dos assinantes'}</span>
                </div>
                <div className="row">
                  <button type="button" className="btn outline sm" onClick={() => edit(item)}><Pencil /> Editar</button>
                  <button type="button" className="btn outline sm" onClick={() => act(() => store.update('support_materials', { id: item.id }, { is_visible: !item.is_visible }), { tables: ['support_materials'], success: item.is_visible ? 'Material ocultado' : 'Material visível para assinantes' })}>
                    {item.is_visible ? <EyeOff /> : <Eye />} {item.is_visible ? 'Ocultar' : 'Mostrar'}
                  </button>
                </div>
              </article>
            )) : <Empty icon={BookOpenText} title="Nenhum material cadastrado">Adicione o primeiro conteúdo desta categoria acima.</Empty>}
          </section>
        ))}
      </div>
    </>
  );
}
