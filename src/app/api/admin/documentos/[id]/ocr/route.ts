import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { NextResponse } from 'next/server';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from '@/lib/env';

export const runtime = 'nodejs';
export const maxDuration = 300;

type JsonRecord = Record<string, unknown>;
type OcrPageInput = { page_number: number; image_data_url: string };

const OCR_MARKER = '--- TEXTO RECONHECIDO POR OCR ---';
const MAX_IMAGE_DATA_URL_LENGTH = 1_700_000;

function cleanText(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function getOutputText(payload: JsonRecord): string {
  if (typeof payload.output_text === 'string') return payload.output_text;
  const output = Array.isArray(payload.output) ? payload.output : [];
  const pieces: string[] = [];
  for (const item of output) {
    if (!item || typeof item !== 'object') continue;
    const content = (item as JsonRecord).content;
    if (!Array.isArray(content)) continue;
    for (const part of content) {
      if (part && typeof part === 'object' && typeof (part as JsonRecord).text === 'string') {
        pieces.push((part as JsonRecord).text as string);
      }
    }
  }
  return pieces.join('\n').trim();
}

function parseJson(text: string): JsonRecord {
  const cleaned = text.trim();
  try {
    const parsed: unknown = JSON.parse(cleaned);
    if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) return parsed as JsonRecord;
  } catch {
    const start = cleaned.indexOf('{');
    const end = cleaned.lastIndexOf('}');
    if (start >= 0 && end > start) {
      const parsed: unknown = JSON.parse(cleaned.slice(start, end + 1));
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) return parsed as JsonRecord;
    }
  }
  throw new Error('A IA respondeu em formato inválido.');
}

export async function POST(request: Request, context: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await context.params;
    if (!/^[0-9a-f-]{36}$/i.test(id)) {
      return NextResponse.json({ error: 'Documento inválido.' }, { status: 400 });
    }

    const body = await request.json() as { pages?: unknown };
    if (!Array.isArray(body.pages) || body.pages.length < 1 || body.pages.length > 2) {
      return NextResponse.json({ error: 'Envie uma ou duas páginas por vez para reconhecimento.' }, { status: 400 });
    }

    const pages: OcrPageInput[] = [];
    for (const raw of body.pages) {
      if (!raw || typeof raw !== 'object') {
        return NextResponse.json({ error: 'Página inválida para OCR.' }, { status: 400 });
      }
      const item = raw as Record<string, unknown>;
      const pageNumber = item.page_number;
      const imageDataUrl = item.image_data_url;
      if (!Number.isInteger(pageNumber) || (pageNumber as number) < 1 || (pageNumber as number) > 1000) {
        return NextResponse.json({ error: 'Número de página inválido.' }, { status: 400 });
      }
      if (
        typeof imageDataUrl !== 'string' ||
        imageDataUrl.length > MAX_IMAGE_DATA_URL_LENGTH ||
        !/^data:image\/jpeg;base64,[A-Za-z0-9+/]+={0,2}$/.test(imageDataUrl)
      ) {
        return NextResponse.json({ error: 'A imagem da página está vazia ou ultrapassa o limite permitido.' }, { status: 413 });
      }
      pages.push({ page_number: pageNumber as number, image_data_url: imageDataUrl });
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
      return NextResponse.json({ error: 'Entre na sua conta administrativa para reconhecer as páginas.' }, { status: 401 });
    }

    const { data: access, error: accessError } = await supabase.rpc('my_access');
    if (accessError || !access?.is_admin) {
      return NextResponse.json({ error: 'Apenas administradores podem reconhecer páginas de PDFs.' }, { status: 403 });
    }

    const { data: document, error: documentError } = await supabase
      .from('source_documents')
      .select('id,page_count,file_status,storage_path')
      .eq('id', id)
      .single();
    if (documentError || !document) {
      return NextResponse.json({ error: 'Documento não encontrado.' }, { status: 404 });
    }
    if (document.file_status !== 'stored' || !document.storage_path) {
      return NextResponse.json({ error: 'O PDF não está armazenado no Supabase.' }, { status: 409 });
    }
    if (document.page_count && pages.some((page) => page.page_number > document.page_count)) {
      return NextResponse.json({ error: 'Uma das páginas não pertence a este PDF.' }, { status: 400 });
    }

    const { data: token, error: tokenError } = await supabase.rpc('admin_get_openrouter_key');
    if (tokenError || typeof token !== 'string' || !token.trim()) {
      return NextResponse.json({ error: 'A chave da IA não está disponível no cofre seguro do Supabase.' }, { status: 503 });
    }

    const instructions = [
      'Faça OCR fiel das páginas de um livro de receitas em português.',
      'Transcreva todo texto legível da imagem, preservando nomes, quantidades, unidades, temperaturas, tempos, títulos e instruções.',
      'Mantenha a ordem de leitura e os parágrafos. Não resuma, não traduza, não corrija e não complete palavras ou receitas por suposição.',
      'Ignore apenas elementos decorativos sem conteúdo textual. Se algum trecho estiver ilegível, marque [ilegível] no ponto correspondente.',
      'Cada imagem vem precedida por seu número de página original. Retorne exatamente o mesmo número.',
      'Responda somente JSON válido no formato {"pages":[{"page_number":1,"page_text":"texto transcrito"}]}. Inclua uma entrada para cada imagem recebida; se não houver texto legível, use page_text vazio.'
    ].join('\n');

    const inputContent: Record<string, unknown>[] = [{ type: 'input_text', text: instructions }];
    for (const page of pages) {
      inputContent.push({ type: 'input_text', text: 'Página original ' + page.page_number + ':' });
      inputContent.push({ type: 'input_image', image_url: page.image_data_url });
    }

    const aiResponse = await fetch('https://openrouter.ai/api/v1/responses', {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'openrouter/free',
        max_output_tokens: 9000,
        text: { format: { type: 'json_object' } },
        input: [{ role: 'user', content: inputContent }],
      }),
      signal: AbortSignal.timeout(240_000),
    });

    const responseText = await aiResponse.text();
    let aiPayload: JsonRecord = {};
    try {
      const decoded: unknown = JSON.parse(responseText);
      if (decoded && typeof decoded === 'object' && !Array.isArray(decoded)) aiPayload = decoded as JsonRecord;
    } catch {
      // A resposta será tratada como erro de provedor abaixo.
    }

    if (!aiResponse.ok) {
      const providerError = aiPayload.error && typeof aiPayload.error === 'object' ? aiPayload.error as JsonRecord : {};
      console.error('OpenRouter OCR failed:', {
        status: aiResponse.status,
        message: cleanText(providerError.message) ?? cleanText(aiPayload.message) ?? responseText.slice(0, 600),
        pageNumbers: pages.map((page) => page.page_number),
      });
      const message = aiResponse.status === 429
        ? 'O limite gratuito de leitura por imagem foi atingido. Tente novamente mais tarde.'
        : aiResponse.status === 401
          ? 'A chave do serviço de leitura não foi aceita.'
          : 'A IA não conseguiu reconhecer estas páginas agora. O restante do PDF continuará disponível para leitura.';
      return NextResponse.json({ error: message, code: 'OCR_PROVIDER_ERROR' }, { status: 502 });
    }

    const outputText = getOutputText(aiPayload);
    if (!outputText) {
      return NextResponse.json({ error: 'A IA não retornou texto reconhecível para estas páginas.' }, { status: 502 });
    }

    let parsed: JsonRecord;
    try {
      parsed = parseJson(outputText);
    } catch {
      console.error('OpenRouter OCR returned invalid JSON:', { pageNumbers: pages.map((page) => page.page_number) });
      return NextResponse.json({ error: 'A resposta do reconhecimento veio em formato inesperado.' }, { status: 502 });
    }

    const returnedPages = Array.isArray(parsed.pages) ? parsed.pages : [];
    const allowedNumbers = new Set(pages.map((page) => page.page_number));
    const recognized = new Map<number, string>();
    for (const raw of returnedPages) {
      if (!raw || typeof raw !== 'object') continue;
      const item = raw as JsonRecord;
      const pageNumber = item.page_number;
      const pageText = cleanText(item.page_text);
      if (Number.isInteger(pageNumber) && allowedNumbers.has(pageNumber as number) && pageText) {
        recognized.set(pageNumber as number, pageText.slice(0, 60_000));
      }
    }

    if (!recognized.size) {
      return NextResponse.json({ recognized_pages: 0, message: 'Nenhum texto legível foi encontrado nas imagens.' });
    }

    const pageNumbers = [...recognized.keys()];
    const { data: existingRows, error: existingError } = await supabase
      .from('document_extracted_pages')
      .select('page_number,page_text')
      .eq('source_document_id', id)
      .in('page_number', pageNumbers);
    if (existingError) {
      console.error('Failed to read existing extracted pages before OCR update:', existingError.message);
      return NextResponse.json({ error: 'Não foi possível preservar o texto já extraído antes de salvar o OCR.' }, { status: 500 });
    }

    const existingByPage = new Map((existingRows ?? []).map((row) => [row.page_number, row.page_text ?? '']));
    const rows = pageNumbers.map((pageNumber) => {
      const existingText = existingByPage.get(pageNumber) ?? '';
      const baseText = existingText.split(OCR_MARKER)[0].trim();
      return {
        source_document_id: id,
        page_number: pageNumber,
        page_text: [baseText, OCR_MARKER, recognized.get(pageNumber)].filter(Boolean).join('\n\n'),
      };
    });

    const { error: saveError } = await supabase
      .from('document_extracted_pages')
      .upsert(rows, { onConflict: 'source_document_id,page_number' });
    if (saveError) {
      console.error('Failed to save OCR text in Supabase:', saveError.message);
      return NextResponse.json({ error: 'O texto foi reconhecido, mas não pôde ser gravado no Supabase.' }, { status: 500 });
    }

    return NextResponse.json({ recognized_pages: rows.length }, { headers: { 'Cache-Control': 'no-store' } });
  } catch (error) {
    console.error('PDF image OCR failed:', error instanceof Error ? error.message : 'unknown error');
    return NextResponse.json({ error: 'Não foi possível reconhecer estas páginas. Tente novamente.' }, { status: 500 });
  }
}
