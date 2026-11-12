'use client';

import { useRef, useState } from 'react';
import { FileText, FileUp, Save } from 'lucide-react';
import { useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { FILE_STATUS_LABELS, PERMISSION_LABELS, useAdminAction } from '@/components/admin';
import { Loading, Notice, PageHead } from '@/components/ui';
import { useToast } from '@/components/toast';
import { useDialog } from '@/components/dialogs';
import type { Recipe, SourceDocument } from '@/lib/types';

const TABLES = ['source_documents', 'recipes', 'source_document_refs', 'admin_audit_logs'] as const;
const MAX_PDF_BYTES = 50 * 1024 * 1024;

async function sha256Hex(file: File): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', await file.arrayBuffer());
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function DocumentCard({ document, recipes, collection }: { document: SourceDocument; recipes: Recipe[]; collection: string }) {
  const { store, supabase } = useSession();
  const act = useAdminAction();
  const { fail, toast } = useToast();
  const { confirm } = useDialog();
  const input = useRef<HTMLInputElement>(null);
  const [permission, setPermission] = useState(document.commercial_permission);
  const [notes, setNotes] = useState(document.permission_notes ?? '');
  const [uploading, setUploading] = useState(false);
  const [importing, setImporting] = useState(false);
  const published = recipes.filter((r) => r.status === 'published').length;
  const dirty = permission !== document.commercial_permission || notes !== (document.permission_notes ?? '');

  async function save() {
    if (document.commercial_permission === 'confirmed' && permission !== 'confirmed' && published > 0) {
      if (!(await confirm({ title: 'Retirar a permissão?', message: `Isso tira do ar ${published} receita(s) publicada(s) deste material imediatamente.`, confirmLabel: 'Retirar permissão', danger: true }))) return;
    }
    await act(() => store.update('source_documents', { id: document.id }, { commercial_permission: permission, permission_notes: notes.trim() || null }), {
      tables: [...TABLES],
      success: permission === 'confirmed' ? 'Permissão confirmada' : 'Permissão atualizada',
    });
  }

  async function importPdf() {
    if (importing || uploading) return;
    setImporting(true);
    try {
      const response = await fetch(`/api/admin/documentos/${document.id}/importar`, { method: 'POST' });
      const result = await response.json() as { error?: string; result?: { created?: number; skipped?: number; support_materials?: number; published?: boolean } };
      if (!response.ok) throw new Error(result.error || 'Não foi possível ler o PDF.');
      const created = result.result?.created ?? 0;
      const skipped = result.result?.skipped ?? 0;
      const materials = result.result?.support_materials ?? 0;
      toast(`${created} receita(s) criada(s), ${materials} material(is) de apoio importado(s)${skipped ? `, ${skipped} ignorada(s) por falta de conteúdo ou duplicidade` : ''}.`);
      window.location.reload();
    } catch (error) {
      fail(error);
    } finally {
      setImporting(false);
    }
  }

  async function upload(file: File | undefined) {
    if (!file || !supabase) return;
    if (file.type !== 'application/pdf') return fail(new Error('Envie um arquivo PDF.'));
    if (file.size > MAX_PDF_BYTES) return fail(new Error('O PDF deve ter no máximo 50 MB.'));
    setUploading(true);
    try {
      const hash = await sha256Hex(file);
      const path = `${document.slug}/${hash.slice(0, 12)}.pdf`;
      const { error } = await supabase.storage.from('source-documents').upload(path, file, { contentType: 'application/pdf', upsert: true });
      if (error) throw error;
      const saved = await act(() => store.update('source_documents', { id: document.id }, { file_status: 'stored', storage_path: path, sha256: hash, file_name: file.name }), {
        tables: [...TABLES],
        success: 'PDF enviado. Iniciando leitura automática…',
      });
      if (saved) await importPdf();
    } catch (error) {
      fail(error);
    } finally {
      setUploading(false);
      if (input.current) input.current.value = '';
    }
  }

  return (
    <section className="panel">
      <div className="spread" style={{ alignItems: 'flex-start', flexWrap: 'wrap' }}>
        <div className="grow">
          <div className="eyebrow">{collection}</div>
          <h2 style={{ margin: '6px 0 4px', fontSize: 22 }}>{document.title}</h2>
          <p className="sub small">
            {[document.author, document.publisher].filter(Boolean).join(' · ') || 'Autoria a confirmar'}
            {document.page_count ? ` · ${document.page_count} páginas` : ''} · idioma {document.language}
          </p>
        </div>
        <div className="row">
          <span className={`pill ${document.file_status === 'stored' ? 'ok' : document.file_status === 'not_provided' ? 'warn' : 'gold'}`}><FileText /> {FILE_STATUS_LABELS[document.file_status]}</span>
          <span className={`pill ${document.commercial_permission === 'confirmed' ? 'ok' : document.commercial_permission === 'unknown' ? 'warn' : 'danger'}`}>Permissão: {PERMISSION_LABELS[document.commercial_permission]}</span>
        </div>
      </div>
      {document.file_name && <div className="original" style={{ marginTop: 10 }}>{document.file_name}{document.sha256 ? `\nsha256 ${document.sha256.slice(0, 16)}…` : ''}</div>}
      {document.import_notes && <p className="muted small" style={{ marginTop: 10 }}>{document.import_notes}</p>}
      {document.measurement_notes && <p className="muted small" style={{ marginTop: 6 }}>Medidas: {document.measurement_notes}</p>}

      <div className="formgrid" style={{ marginTop: 14 }}>
        <div className="group">
          <label htmlFor={`perm-${document.id}`}>Autorização para uso no Clube</label>
          <select
            id={`perm-${document.id}`}
            className="select"
            value={permission}
            onChange={(e) => {
              const next = e.target.value as SourceDocument['commercial_permission'];
              setPermission(next);
            }}
          >
            {Object.entries(PERMISSION_LABELS).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
        </div>
        <div className="group">
          <label htmlFor={`notes-${document.id}`}>Observação (opcional)</label>
          <input id={`notes-${document.id}`} className="field" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Ex.: material de minha autoria ou autorização concedida pelo autor" />
        </div>
      </div>
      <div className="row" style={{ marginTop: 12 }}>
        <button type="button" className="btn dark sm" disabled={!dirty} onClick={save}><Save /> Salvar permissão</button>
        {supabase ? (
          <>
            <button type="button" className="btn outline sm" disabled={uploading || importing} onClick={() => input.current?.click()}>
              <FileUp /> {uploading ? 'Enviando…' : document.file_status === 'stored' ? 'Substituir PDF' : 'Enviar PDF'}
            </button>
            {document.file_status === 'stored' && (
              <button type="button" className="btn dark sm" disabled={uploading || importing} onClick={importPdf}>
                {importing ? 'Lendo e cadastrando…' : 'Ler PDF e cadastrar receitas'}
              </button>
            )}
            <input ref={input} type="file" accept="application/pdf" hidden onChange={(e) => upload(e.target.files?.[0])} />
          </>
        ) : (
          <span className="muted small">O envio do PDF fica disponível com o Supabase conectado.</span>
        )}
        <span className="muted small">{recipes.length} item(ns) do catálogo · {published} no ar</span>
      </div>
    </section>
  );
}

export default function AdminDocuments() {
  const { rows: documents } = useTable('source_documents', { order: [['created_at', 'asc']] });
  const { rows: recipes } = useTable('recipes');
  const { rows: collections } = useTable('collections', { order: [['position', 'asc']] });
  if (!documents || !recipes || !collections) return <Loading />;
  const order = new Map(collections.map((c, i) => [c.id, i]));
  const sorted = [...documents].sort((a, b) => (order.get(a.collection_id ?? '') ?? 99) - (order.get(b.collection_id ?? '') ?? 99));

  return (
    <>
      <PageHead eyebrow="Materiais de origem" title="Documentos." sub="Envie um PDF: o sistema lê as páginas, separa receitas, ingredientes, preparo e materiais de apoio e cadastra o conteúdo no catálogo." />
      <div style={{ marginBottom: 16 }}>
        <Notice>
          <b>Autorização:</b> confirme uma única vez por material quando ele for de sua autoria ou houver licença/autorização para uso no Clube. O sistema registra quem confirmou e a data. Se a autorização for retirada, as receitas publicadas daquele material saem do ar automaticamente.
        </Notice>
      </div>
      <div className="stack">
        {sorted.map((document) => (
          <DocumentCard
            key={`${document.id}:${document.updated_at}`}
            document={document}
            recipes={recipes.filter((r) => r.source_document_id === document.id)}
            collection={collections.find((c) => c.id === document.collection_id)?.name ?? 'Sem coleção'}
          />
        ))}
      </div>
    </>
  );
}
