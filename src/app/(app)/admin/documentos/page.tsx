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
  const { fail } = useToast();
  const { confirm } = useDialog();
  const input = useRef<HTMLInputElement>(null);
  const [permission, setPermission] = useState(document.commercial_permission);
  const [notes, setNotes] = useState(document.permission_notes ?? '');
  const [uploading, setUploading] = useState(false);
  const published = recipes.filter((r) => r.status === 'published').length;
  const dirty = permission !== document.commercial_permission || notes !== (document.permission_notes ?? '');

  async function save() {
    if (document.commercial_permission === 'confirmed' && permission !== 'confirmed' && published > 0) {
      if (!(await confirm({ title: 'Retirar a permissão?', message: `Isso tira do ar ${published} receita(s) publicada(s) deste material imediatamente.`, confirmLabel: 'Retirar permissão', danger: true }))) return;
    }
    if (permission === 'confirmed' && !notes.trim()) return fail(new Error('Registre em “Observações” como a permissão foi obtida (ex.: autorização por escrito, licença adquirida).'));
    await act(() => store.update('source_documents', { id: document.id }, { commercial_permission: permission, permission_notes: notes.trim() || null }), {
      tables: [...TABLES],
      success: permission === 'confirmed' ? 'Permissão confirmada' : 'Permissão atualizada',
    });
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
      await act(() => store.update('source_documents', { id: document.id }, { file_status: 'stored', storage_path: path, sha256: hash, file_name: document.file_name ?? file.name }), {
        tables: [...TABLES],
        success: 'PDF guardado no cofre privado',
      });
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
          <label htmlFor={`perm-${document.id}`}>Permissão de uso comercial</label>
          <select
            id={`perm-${document.id}`}
            className="select"
            value={permission}
            onChange={(e) => {
              const next = e.target.value as SourceDocument['commercial_permission'];
              // ao confirmar, a justificativa precisa ser escrita de novo (não vale a observação anterior)
              if (next === 'confirmed' && document.commercial_permission !== 'confirmed' && notes === (document.permission_notes ?? '')) setNotes('');
              setPermission(next);
            }}
          >
            {Object.entries(PERMISSION_LABELS).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
        </div>
        <div className="group">
          <label htmlFor={`notes-${document.id}`}>Observações da permissão</label>
          <input id={`notes-${document.id}`} className="field" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder={permission === 'confirmed' ? 'Como a permissão foi obtida? (obrigatório)' : 'Ex.: autorização por e-mail da autora em 12/11/2026'} />
        </div>
      </div>
      <div className="row" style={{ marginTop: 12 }}>
        <button type="button" className="btn dark sm" disabled={!dirty} onClick={save}><Save /> Salvar permissão</button>
        {supabase ? (
          <>
            <button type="button" className="btn outline sm" disabled={uploading} onClick={() => input.current?.click()}>
              <FileUp /> {uploading ? 'Enviando…' : document.file_status === 'stored' ? 'Substituir PDF no cofre' : 'Enviar PDF ao cofre privado'}
            </button>
            <input ref={input} type="file" accept="application/pdf" hidden onChange={(e) => upload(e.target.files?.[0])} />
          </>
        ) : (
          <span className="muted small">O envio do PDF ao cofre privado fica disponível com o Supabase conectado.</span>
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
      <PageHead eyebrow="Materiais de origem" title="Documentos." sub="Os PDFs originais ficam em um cofre privado, acessível só a administradores. Nenhuma receita entra no ar sem a permissão comercial do material confirmada." />
      <div style={{ marginBottom: 16 }}>
        <Notice>
          <b>Permissão comercial:</b> confirme apenas quando houver autorização do autor ou licença que permita o uso no Clube, e registre como ela foi obtida. Se a permissão for retirada, as receitas daquele material saem do ar automaticamente.
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
