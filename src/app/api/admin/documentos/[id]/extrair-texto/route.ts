import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { NextResponse } from 'next/server';
import { getDocument } from 'pdfjs-dist/legacy/build/pdf.mjs';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from '@/lib/env';

export const runtime = 'nodejs';
export const maxDuration = 300;

const MAX_PDF_BYTES = 35 * 1024 * 1024;
const MAX_EXTRACTED_CHARACTERS = 8_000_000;

type ExtractedPage = {
  source_document_id: string;
  page_number: number;
  page_text: string;
};

export async function POST(_request: Request, context: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await context.params;
    if (!/^[0-9a-f-]{36}$/i.test(id)) {
      return NextResponse.json({ error: 'Documento inválido.' }, { status: 400 });
    }

    const cookieStore = await cookies();
    const supabase = createServerClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      cookies: {
        getAll: () => cookieStore.getAll(),
        setAll: (values) => values.forEach(({ name, value, options }) => cookieStore.set(name, value, options)),
      },
    });

    const { data: auth, error: authError } = await supabase.auth.getUser();
    if (authError || !auth.user) {
      return NextResponse.json({ error: 'Entre na sua conta administrativa para extrair o PDF.' }, { status: 401 });
    }

    const { data: access, error: accessError } = await supabase.rpc('my_access');
    if (accessError || !access?.is_admin) {
      return NextResponse.json({ error: 'Apenas administradores podem extrair PDFs.' }, { status: 403 });
    }

    const { data: document, error: documentError } = await supabase
      .from('source_documents')
      .select('id,title,file_name,file_status,storage_path')
      .eq('id', id)
      .single();
    if (documentError || !document) {
      return NextResponse.json({ error: 'Documento não encontrado.' }, { status: 404 });
    }
    if (document.file_status !== 'stored' || !document.storage_path) {
      return NextResponse.json({ error: 'Este documento ainda não possui um PDF armazenado.' }, { status: 409 });
    }

    const { data: file, error: fileError } = await supabase.storage
      .from('source-documents')
      .download(document.storage_path);
    if (fileError || !file) {
      return NextResponse.json({ error: 'Não foi possível abrir o PDF privado no Supabase.' }, { status: 422 });
    }
    if (file.size > MAX_PDF_BYTES) {
      return NextResponse.json({ error: 'O PDF ultrapassa o limite de 35 MB para extração.' }, { status: 413 });
    }

    const pdf = await getDocument({
      data: new Uint8Array(await file.arrayBuffer()),
      useSystemFonts: true,
      isEvalSupported: false,
      disableFontFace: true,
    }).promise;

    const pages: ExtractedPage[] = [];
    let characters = 0;
    try {
      for (let pageNumber = 1; pageNumber <= pdf.numPages; pageNumber += 1) {
        const page = await pdf.getPage(pageNumber);
        const content = await page.getTextContent();
        const text = content.items
          .map((item) => {
            if (!('str' in item) || typeof item.str !== 'string') return '';
            return item.str + ('hasEOL' in item && item.hasEOL ? '\n' : ' ');
          })
          .join('')
          .replace(/[ \t]+/g, ' ')
          .replace(/ *\n */g, '\n')
          .trim();

        characters += text.length;
        if (characters > MAX_EXTRACTED_CHARACTERS) {
          throw new Error('O texto extraído ultrapassou o limite seguro de 8 milhões de caracteres.');
        }
        pages.push({ source_document_id: id, page_number: pageNumber, page_text: text });
        page.cleanup();
      }
    } finally {
      await pdf.destroy();
    }

    const nonEmptyPages = pages.filter((page) => page.page_text.length > 0).length;
    if (characters < 80 || nonEmptyPages === 0) {
      return NextResponse.json({
        error: 'Este PDF parece ser formado por páginas escaneadas ou imagens, sem texto selecionável. A extração local não usa OCR; não gravei nenhum resultado. Será necessário um passo de reconhecimento de texto.',
        code: 'PDF_WITHOUT_TEXT_LAYER',
      }, { status: 422 });
    }

    for (let start = 0; start < pages.length; start += 100) {
      const batch = pages.slice(start, start + 100);
      const { error } = await supabase
        .from('document_extracted_pages')
        .upsert(batch, { onConflict: 'source_document_id,page_number' });
      if (error) throw error;
    }

    const { error: cleanupError } = await supabase
      .from('document_extracted_pages')
      .delete()
      .eq('source_document_id', id)
      .gt('page_number', pages.length);
    if (cleanupError) throw cleanupError;

    return NextResponse.json({
      ok: true,
      pages: pages.length,
      pages_with_text: nonEmptyPages,
      characters,
      document_title: document.title,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Falha inesperada ao extrair o texto do PDF.';
    console.error('PDF text extraction failed:', message);
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
