import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { NextResponse } from 'next/server';
import { PDFDocument } from 'pdf-lib';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from '@/lib/env';

export const runtime = 'nodejs';
export const maxDuration = 300;

type JsonRecord = Record<string, unknown>;

function cleanNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && /^\s*-?\d+(?:[.,]\d+)?\s*$/.test(value)) {
    const parsed = Number(value.trim().replace(',', '.'));
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function cleanInteger(value: unknown): number | null {
  const n = cleanNumber(value);
  return n !== null && Number.isInteger(n) ? n : null;
}

function cleanPage(value: unknown): number | null {
  const n = cleanInteger(value);
  return n !== null && n > 0 ? n : null;
}

function cleanText(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function parseModelJson(value: string): JsonRecord {
  const cleaned = value.trim().replace(/^\u0060\u0060\u0060(?:json)?\s*/i, '').replace(/\s*\u0060\u0060\u0060$/, '');
  const parsed: unknown = JSON.parse(cleaned);
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('O modelo não retornou um objeto JSON.');
  return parsed as JsonRecord;
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


const MAX_PDF_PART_BYTES = 4 * 1024 * 1024;

async function createPdfParts(bytes: Uint8Array): Promise<Array<{ bytes: Uint8Array; firstPage: number; lastPage: number }>> {
  const source = await PDFDocument.load(bytes, { updateMetadata: false });
  const pageCount = source.getPageCount();
  if (!pageCount) throw new Error('O PDF não contém páginas legíveis.');

  const parts: Array<{ bytes: Uint8Array; firstPage: number; lastPage: number }> = [];
  async function splitRange(firstPage: number, lastPage: number): Promise<void> {
    const part = await PDFDocument.create();
    const indices = Array.from({ length: lastPage - firstPage + 1 }, (_, index) => firstPage + index);
    const copiedPages = await part.copyPages(source, indices);
    copiedPages.forEach((page) => part.addPage(page));
    const partBytes = await part.save({ useObjectStreams: true });

    if (partBytes.byteLength <= MAX_PDF_PART_BYTES) {
      parts.push({ bytes: partBytes, firstPage, lastPage });
      return;
    }
    if (firstPage === lastPage) {
      throw new Error(`A página ${firstPage + 1} sozinha ultrapassa o limite seguro de leitura.`);
    }
    const middle = Math.floor((firstPage + lastPage) / 2);
    await splitRange(firstPage, middle);
    await splitRange(middle + 1, lastPage);
  }

  await splitRange(0, pageCount - 1);
  return parts;
}

function shiftSourcePages(payload: JsonRecord, offset: number): JsonRecord {
  const shift = (value: unknown): number | null => {
    const page = cleanPage(value);
    return page === null ? null : page + offset;
  };
  const recipes = Array.isArray(payload.recipes) ? payload.recipes as JsonRecord[] : [];
  for (const recipe of recipes) {
    recipe.source_page_start = shift(recipe.source_page_start);
    recipe.source_page_end = shift(recipe.source_page_end);
    if (Array.isArray(recipe.ingredients)) {
      for (const ingredient of recipe.ingredients as JsonRecord[]) ingredient.source_page = shift(ingredient.source_page);
    }
    if (Array.isArray(recipe.steps)) {
      for (const step of recipe.steps as JsonRecord[]) step.source_page = shift(step.source_page);
    }
  }
  if (Array.isArray(payload.support_materials)) {
    for (const item of payload.support_materials as JsonRecord[]) item.source_page = shift(item.source_page);
  }
  return payload;
}

function normalizePayload(input: JsonRecord): JsonRecord {
  const rawRecipes = Array.isArray(input.recipes) ? input.recipes : [];
  const recipes = rawRecipes.slice(0, 100).map((raw) => {
    const recipe = raw && typeof raw === 'object' ? raw as JsonRecord : {};
    const rawIngredients = Array.isArray(recipe.ingredients) ? recipe.ingredients : [];
    const rawSteps = Array.isArray(recipe.steps) ? recipe.steps : [];
    return {
      title: cleanText(recipe.title),
      original_title: cleanText(recipe.original_title),
      original_language: cleanText(recipe.original_language) ?? 'pt-BR',
      description: cleanText(recipe.description),
      difficulty: cleanText(recipe.difficulty)?.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '') ?? null,
      yield_text: cleanText(recipe.yield_text),
      prep_minutes: cleanInteger(recipe.prep_minutes),
      cook_minutes: cleanInteger(recipe.cook_minutes),
      bake_minutes: cleanInteger(recipe.bake_minutes),
      chill_minutes: cleanInteger(recipe.chill_minutes),
      rest_minutes: cleanInteger(recipe.rest_minutes),
      source_page_start: cleanPage(recipe.source_page_start),
      source_page_end: cleanPage(recipe.source_page_end),
      ingredients: rawIngredients.slice(0, 150).map((rawIngredient) => {
        const ingredient = rawIngredient && typeof rawIngredient === 'object' ? rawIngredient as JsonRecord : {};
        return {
          display_name: cleanText(ingredient.display_name),
          quantity: cleanNumber(ingredient.quantity),
          quantity_max: cleanNumber(ingredient.quantity_max),
          unit: cleanText(ingredient.unit),
          quantity_text: cleanText(ingredient.quantity_text),
          preparation: cleanText(ingredient.preparation),
          is_optional: ingredient.is_optional === true,
          original_text: cleanText(ingredient.original_text),
          source_page: cleanPage(ingredient.source_page),
        };
      }),
      steps: rawSteps.slice(0, 100).map((rawStep) => {
        const step = rawStep && typeof rawStep === 'object' ? rawStep as JsonRecord : {};
        return {
          instruction: cleanText(step.instruction),
          original_text: cleanText(step.original_text),
          tip: cleanText(step.tip),
          source_page: cleanPage(step.source_page),
        };
      }),
    };
  }).filter((recipe) => recipe.title && recipe.ingredients.some((item) => item.display_name) && recipe.steps.some((item) => item.instruction));

  const rawMaterials = Array.isArray(input.support_materials) ? input.support_materials : [];
  const support_materials = rawMaterials.slice(0, 200).map((raw) => {
    const item = raw && typeof raw === 'object' ? raw as JsonRecord : {};
    const kind = cleanText(item.kind)?.toLowerCase();
    return {
      kind: ['utensilios', 'ingredientes', 'dicas', 'orientacoes'].includes(kind ?? '') ? kind : 'orientacoes',
      title: cleanText(item.title),
      body: cleanText(item.body),
      source_page: cleanPage(item.source_page),
    };
  }).filter((item) => item.title && item.body);

  const collection = input.collection && typeof input.collection === 'object'
    ? input.collection as JsonRecord
    : {};
  return {
    collection: {
      name: cleanText(collection.name),
      description: cleanText(collection.description),
    },
    recipes,
    support_materials,
  };
}

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
    if (authError || !auth.user) return NextResponse.json({ error: 'Entre na sua conta administrativa para importar o PDF.' }, { status: 401 });

    const { data: access, error: accessError } = await supabase.rpc('my_access');
    if (accessError || !access?.is_admin) return NextResponse.json({ error: 'Apenas administradores podem importar PDFs.' }, { status: 403 });

    const { data: document, error: documentError } = await supabase
      .from('source_documents')
      .select('id,title,file_name,file_status,storage_path,commercial_permission')
      .eq('id', id)
      .single();
    if (documentError || !document) return NextResponse.json({ error: 'Documento não encontrado.' }, { status: 404 });
    if (document.file_status !== 'stored' || !document.storage_path) {
      return NextResponse.json({ error: 'Envie o PDF antes de iniciar a leitura.' }, { status: 409 });
    }

    const { data: token, error: tokenError } = await supabase.rpc('admin_get_openrouter_key');
    if (tokenError || typeof token !== 'string' || !token.trim()) {
      return NextResponse.json({
        error: 'A leitura automática está pronta, mas falta cadastrar a chave do OpenRouter no cofre seguro do Supabase.',
        code: 'OPENROUTER_NOT_CONFIGURED',
      }, { status: 503 });
    }

    const { data: file, error: fileError } = await supabase.storage.from('source-documents').download(document.storage_path);
    if (fileError || !file) return NextResponse.json({ error: 'Não foi possível abrir o PDF armazenado. Confira o envio do arquivo.' }, { status: 422 });
    if (file.size > 35 * 1024 * 1024) return NextResponse.json({ error: 'Este PDF ultrapassa o limite de 35 MB para leitura automática.' }, { status: 413 });


    let pdfParts: Array<{ bytes: Uint8Array; firstPage: number; lastPage: number }>;
    try {
      pdfParts = await createPdfParts(new Uint8Array(await file.arrayBuffer()));
    } catch (splitError) {
      const reason = splitError instanceof Error ? splitError.message : 'PDF inválido ou protegido.';
      return NextResponse.json({ error: `Não consegui dividir este PDF para leitura: ${reason} Nenhuma receita foi cadastrada.`, code: 'PDF_SPLIT_FAILED' }, { status: 422 });
    }

    const promptInstructions = [
      'Você é um sistema de transcrição fiel de livros e apostilas culinárias para uma biblioteca de receitas em português brasileiro.',
      'Leia integralmente este trecho do PDF, incluindo texto, tabelas e páginas escaneadas. Extraia cada receita individualmente e os materiais de apoio visíveis neste trecho.',
      'Este arquivo é uma parte de um PDF maior. Não presuma que o conteúdo de uma receita continua neste trecho; se ingredientes ou etapas estiverem incompletos por causa do corte, omita a receita.',
      'Não invente, estime, complete nem corrija ingredientes, quantidades, unidades, temperaturas, tempos ou etapas. Se um dado não estiver legível ou não constar, use null ou deixe o campo ausente.',
      'Não misture receitas. Preserve a ordem, o texto e as medidas. Mantenha frações ou quantidades ambíguas em quantity_text e deixe quantity null.',
      'Só inclua uma receita em recipes se conseguir identificar ao menos um ingrediente e uma etapa de preparo. Receitas incompletas não devem ser inventadas; omita-as.',
      'Para cada receita retorne: title, original_title, original_language, description, difficulty (facil, media, dificil ou null), yield_text, prep_minutes, cook_minutes, bake_minutes, chill_minutes, rest_minutes, source_page_start, source_page_end, ingredients e steps.',
      'Cada ingrediente deve ter display_name, quantity (número ou null), quantity_max (número ou null), unit, quantity_text, preparation, is_optional, original_text e source_page.',
      'Cada etapa deve ter instruction, original_text, tip e source_page.',
      'Extraia também utensílios, ingredientes básicos, dicas e orientações gerais em support_materials, com kind (utensilios, ingredientes, dicas ou orientacoes), title, body e source_page.',
      'Identifique o nome e a descrição da categoria em collection.name e collection.description. Se o documento não indicar uma categoria clara, use o título do próprio documento como nome.',
      'Responda somente com JSON válido, sem markdown, no formato: {"collection":{"name":"...","description":null},"recipes":[{"title":"...","ingredients":[{"display_name":"...","quantity":null,"quantity_max":null,"unit":null,"quantity_text":"...","preparation":null,"is_optional":false,"original_text":"...","source_page":1}],"steps":[{"instruction":"...","original_text":"...","tip":null,"source_page":1}]}],"support_materials":[{"kind":"dicas","title":"...","body":"...","source_page":1}]}',
      'Os números de página devem ser relativos a este arquivo de parte, começando em 1. A aplicação ajustará automaticamente para a página correspondente no PDF original. Se não tiver certeza da página, use null.',
    ].join('\\n');

    const allRecipes: JsonRecord[] = [];
    const allSupportMaterials: JsonRecord[] = [];
    let collectionInfo: JsonRecord = {};

    for (let partIndex = 0; partIndex < pdfParts.length; partIndex += 1) {
      const part = pdfParts[partIndex];
      const base64 = Buffer.from(part.bytes).toString('base64');
      const prompt = [
        promptInstructions,
        `Parte ${partIndex + 1} de ${pdfParts.length}. Ela corresponde às páginas ${part.firstPage + 1} a ${part.lastPage + 1} do PDF original.`,
        `Título do documento: ${document.title}.`,
      ].join('\\n');

      const aiResponse = await fetch('https://openrouter.ai/api/v1/responses', {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          model: 'openrouter/free',
          max_output_tokens: 48000,
          plugins: [{ id: 'file-parser', pdf: { engine: 'cloudflare-ai' } }],
          text: { format: { type: 'json_object' } },
          input: [{
            role: 'user',
            content: [
              { type: 'input_text', text: prompt },
              { type: 'input_file', filename: `${document.file_name || 'receitas'}.parte-${partIndex + 1}.pdf`, file_data: `data:application/pdf;base64,${base64}` },
            ],
          }],
        }),
        signal: AbortSignal.timeout(240_000),
      });

      const aiResponseText = await aiResponse.text();
      let aiPayload: JsonRecord = {};
      try {
        const decoded: unknown = JSON.parse(aiResponseText);
        if (decoded && typeof decoded === 'object' && !Array.isArray(decoded)) aiPayload = decoded as JsonRecord;
      } catch {
        // Keep an empty payload; status and a bounded response excerpt are logged below.
      }

      if (!aiResponse.ok) {
        const status = aiResponse.status;
        const providerError = aiPayload.error && typeof aiPayload.error === 'object'
          ? aiPayload.error as JsonRecord
          : {};
        const providerMessage = cleanText(providerError.message) ?? cleanText(aiPayload.message);
        console.error('OpenRouter PDF part request failed:', {
          part: partIndex + 1,
          totalParts: pdfParts.length,
          status,
          message: providerMessage ?? 'Resposta sem mensagem de erro',
          responseExcerpt: providerMessage ? undefined : aiResponseText.slice(0, 1200),
        });
        const isSizeError = /exceeds the maximum size|file.*too large|maximum.*file.*size/i.test(providerMessage ?? '');
        const message = isSizeError ? 'Mesmo após dividir o PDF, o leitor gratuito recusou uma das partes por tamanho. Nenhuma receita foi cadastrada.'
          : status === 401 ? 'A chave do OpenRouter não foi aceita. Confira o segredo cadastrado no cofre do Supabase.'
          : status === 402 ? 'O OpenRouter recusou a solicitação por limite ou saldo. Nenhuma receita foi cadastrada.'
          : status === 403 ? 'O OpenRouter não autorizou esta solicitação. Verifique as permissões da chave.'
          : status === 429 ? `O limite gratuito do OpenRouter foi atingido durante a parte ${partIndex + 1} de ${pdfParts.length}. Nenhuma receita foi cadastrada; aguarde e tente novamente.`
          : status === 400 ? 'O OpenRouter rejeitou uma parte do PDF. O motivo técnico foi registrado para correção; nenhuma receita foi cadastrada.'
          : 'O serviço gratuito de leitura não respondeu corretamente. Nenhuma receita foi cadastrada.';
        return NextResponse.json({ error: message, code: isSizeError ? 'PDF_PART_TOO_LARGE' : 'OPENROUTER_ERROR', provider_status: status, part: partIndex + 1, total_parts: pdfParts.length }, { status: 502 });
      }

      const outputText = getOutputText(aiPayload);
      if (!outputText) {
        return NextResponse.json({ error: `A IA não retornou conteúdo legível na parte ${partIndex + 1} de ${pdfParts.length}. Nenhuma receita foi cadastrada.`, code: 'PDF_PART_EMPTY' }, { status: 502 });
      }
      const parsed = parseModelJson(outputText);
      const normalized = shiftSourcePages(normalizePayload(parsed), part.firstPage);
      if (normalized.collection && typeof normalized.collection === 'object') {
        const candidate = normalized.collection as JsonRecord;
        if (!collectionInfo.name && candidate.name) collectionInfo = candidate;
      }
      if (Array.isArray(normalized.recipes)) allRecipes.push(...normalized.recipes as JsonRecord[]);
      if (Array.isArray(normalized.support_materials)) allSupportMaterials.push(...normalized.support_materials as JsonRecord[]);
    }

    const payload: JsonRecord = {
      collection: collectionInfo,
      recipes: allRecipes.slice(0, 100),
      support_materials: allSupportMaterials.slice(0, 200),
    };
    if ((!Array.isArray(payload.recipes) || payload.recipes.length === 0) && (!Array.isArray(payload.support_materials) || payload.support_materials.length === 0)) {
      return NextResponse.json({ error: 'Não encontrei receitas completas com ingredientes e modo de preparo neste PDF. Nenhuma receita foi cadastrada.' }, { status: 422 });
    }

    const { data: imported, error: importError } = await supabase.rpc('admin_import_pdf_recipes', {
      p_document_id: id,
      p_payload: payload,
    });
    if (importError) {
      console.error('Falha ao salvar importação do PDF:', importError.message);
      return NextResponse.json({ error: 'O PDF foi lido, mas não foi possível salvar as receitas no catálogo. Nenhum dado foi confirmado.' }, { status: 500 });
    }

    return NextResponse.json({ result: imported, parts_processed: pdfParts.length }, { headers: { 'Cache-Control': 'no-store' } });
  } catch (error) {
    console.error('Falha na importação automática de PDF:', error instanceof Error ? error.message : 'erro desconhecido');
    return NextResponse.json({ error: 'Não foi possível concluir a leitura automática. Tente novamente.' }, { status: 500 });
  }
}
