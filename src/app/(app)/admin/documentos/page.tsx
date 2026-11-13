'use client';

import { useRef, useState } from 'react';
import { GlobalWorkerOptions, getDocument } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { FileText, FileUp, Save } from 'lucide-react';
import { useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { FILE_STATUS_LABELS, PERMISSION_LABELS, useAdminAction } from '@/components/admin';
import { Loading, Notice, PageHead } from '@/components/ui';
import { useToast } from '@/components/toast';
import { useDialog } from '@/components/dialogs';
import type { Recipe, SourceDocument } from '@/lib/types';

const TABLES = ['source_documents', 'recipes', 'source_document_refs', 'admin_audit_logs'] as const;
const MAX_PDF_BYTES = 35 * 1024 * 1024;
const MAX_EXTRACTED_CHARACTERS = 8_000_000;

if (typeof window !== 'undefined') {
  GlobalWorkerOptions.workerSrc = '/pdf.worker.mjs';
}

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
  const [extracting, setExtracting] = useState(false);
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
    if (importing) return;
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

  async function extractText(storagePath?: string): Promise<boolean> {
    if (extracting || importing || !supabase) return false;
    setExtracting(true);
    try {
      const { data: access, error: accessError } = await supabase.rpc('my_access');
      if (accessError || !access?.is_admin) throw new Error('Apenas administradores podem extrair PDFs.');

      const pdfPath = storagePath ?? document.storage_path;
      if ((!storagePath && document.file_status !== 'stored') || !pdfPath) {
        throw new Error('Este documento ainda não possui um PDF armazenado.');
      }

      const { data: file, error: fileError } = await supabase.storage
        .from('source-documents')
        .download(pdfPath);
      if (fileError || !file) throw new Error('Não foi possível abrir o PDF privado no Supabase.');
      if (file.size > MAX_PDF_BYTES) throw new Error('O PDF ultrapassa o limite de 35 MB para extração.');

      const pdf = await getDocument({
        data: new Uint8Array(await file.arrayBuffer()),
        useSystemFonts: true,
        isEvalSupported: false,
        disableFontFace: true,
      }).promise;

      const pages: { source_document_id: string; page_number: number; page_text: string }[] = [];
      const imagePages: { page_number: number; image_data_url: string }[] = [];
      let characters = 0;
      try {
        for (let pageNumber = 1; pageNumber <= pdf.numPages; pageNumber += 1) {
          const page = await pdf.getPage(pageNumber);
          const content = await page.getTextContent();
          const text = content.items
            .map((item) => ('str' in item && typeof item.str === 'string' ? item.str : ''))
            .join(' ')
            .replace(/\s+/g, ' ')
            .trim();
          characters += text.length;
          if (characters > MAX_EXTRACTED_CHARACTERS) {
            throw new Error('O texto extraído ultrapassou o limite seguro de 8 milhões de caracteres.');
          }
          pages.push({ source_document_id: document.id, page_number: pageNumber, page_text: text });

          // Páginas com pouco texto selecionável podem conter a receita como imagem.
          // Renderizamos no navegador; a imagem é enviada apenas para OCR e não é armazenada.
          if (text.length < 100 && imagePages.length < 40) {
            try {
              const baseViewport = page.getViewport({ scale: 1 });
              const scale = Math.min(1.5, 1600 / baseViewport.width);
              const viewport = page.getViewport({ scale });
              const canvas = window.document.createElement('canvas');
              canvas.width = Math.ceil(viewport.width);
              canvas.height = Math.ceil(viewport.height);
              const context = canvas.getContext('2d');
              if (context) {
                await page.render({ canvasContext: context, viewport }).promise;
                const imageDataUrl = canvas.toDataURL('image/jpeg', 0.76);
                if (imageDataUrl.length <= 1_700_000) {
                  imagePages.push({ page_number: pageNumber, image_data_url: imageDataUrl });
                }
              }
              canvas.width = 0;
              canvas.height = 0;
            } catch (renderError) {
              console.warn('Não foi possível preparar a página para OCR:', pageNumber, renderError);
            }
          }
          page.cleanup();
        }
      } finally {
        await pdf.destroy();
      }

      const pagesWithText = pages.filter((page) => page.page_text.length > 0).length;
      if (characters < 80 && imagePages.length === 0) {
        throw new Error('Não foi possível extrair texto nem preparar páginas para OCR. Confira se o PDF está íntegro.');
      }

      for (let start = 0; start < pages.length; start += 100) {
        const { error } = await supabase
          .from('document_extracted_pages')
          .upsert(pages.slice(start, start + 100), { onConflict: 'source_document_id,page_number' });
        if (error) throw error;
      }

      const { error: cleanupError } = await supabase
        .from('document_extracted_pages')
        .delete()
        .eq('source_document_id', document.id)
        .gt('page_number', pages.length);
      if (cleanupError) throw cleanupError;

      let ocrPagesRead = 0;
      let ocrPagesFailed = 0;
      for (let start = 0; start < imagePages.length; start += 2) {
        const batch = imagePages.slice(start, start + 2);
        try {
          const response = await fetch(`/api/admin/documentos/${document.id}/ocr`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ pages: batch }),
          });
          const result = await response.json() as { error?: string; recognized_pages?: number };
          if (!response.ok) throw new Error(result.error || 'O OCR não conseguiu ler esta página.');
          ocrPagesRead += result.recognized_pages ?? 0;
        } catch (ocrError) {
          ocrPagesFailed += batch.length;
          console.warn('Falha no OCR das páginas:', batch.map((page) => page.page_number), ocrError);
        }
      }

      const ocrSummary = imagePages.length
        ? ` OCR: ${ocrPagesRead} página(s) reconhecida(s)${ocrPagesFailed ? `, ${ocrPagesFailed} com falha` : ''}.`
        : '';
      const cappedSummary = imagePages.length === 40 ? ' O limite de 40 páginas com imagem por leitura foi atingido.' : '';
      toast(`Texto extraído: ${pages.length} páginas, ${pagesWithText} com texto e ${characters.toLocaleString('pt-BR')} caracteres. O conteúdo foi gravado no Supabase.${ocrSummary}${cappedSummary}`);
      return true;
    } catch (error) {
      fail(error);
      return false;
    } finally {
      setExtracting(false);
    }
  }

  async function readAndImportPdf(storagePath?: string) {
    if (extracting || importing) return;

    // Ao reler um documento já processado, aproveita o texto persistido no
    // Supabase. Evita baixar/renderizar o PDF outra vez antes de importar.
    // Quando um novo arquivo é enviado (storagePath informado), a extração
    // sempre é refeita para não reutilizar texto de uma versão anterior.
    let extracted = false;
    if (!storagePath && supabase && document.file_status === 'stored') {
      try {
        const { data: savedPages, error: savedPagesError } = await supabase
          .from('document_extracted_pages')
          .select('page_text')
          .eq('source_document_id', document.id);
        if (savedPagesError) throw savedPagesError;
        const savedCharacters = (savedPages ?? []).reduce(
          (total, page) => total + (page.page_text?.trim().length ?? 0),
          0,
        );
        extracted = savedCharacters >= 80;
      } catch (error) {
        console.warn('Não foi possível reutilizar o texto salvo; uma nova extração será tentada.', error);
      }
    }

    if (!extracted) {
      extracted = await extractText(storagePath);
    }
    if (!extracted) return;
    await importPdf();
  }

  async function upload(file: File | undefined) {
    if (!file || !supabase) return;
    if (file.type !== 'application/pdf') return fail(new Error('Envie um arquivo PDF.'));
    if (file.size > MAX_PDF_BYTES) return fail(new Error('O PDF deve ter no máximo 35 MB.'));
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
      if (saved) await readAndImportPdf(path);
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
            <button type="button" className="btn outline sm" disabled={uploading || importing || extracting} onClick={() => input.current?.click()}>
              <FileUp /> {uploading ? 'Enviando…' : document.file_status === 'stored' ? 'Substituir PDF' : 'Enviar PDF'}
            </button>
            {document.file_status === 'stored' && (
              <button type="button" className="btn dark sm" disabled={uploading || importing || extracting} onClick={() => readAndImportPdf()}>
                {extracting ? 'Extraindo texto…' : importing ? 'Organizando e cadastrando…' : 'Ler PDF e cadastrar receitas'}
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
