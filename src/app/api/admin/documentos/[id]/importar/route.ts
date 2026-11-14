import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { NextResponse } from 'next/server';
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
  const candidates = [cleaned];
  // Alguns modelos gratuitos acrescentam uma frase antes/depois do JSON.
  // Localiza o primeiro objeto completo sem confundir chaves dentro de strings.
  const start = cleaned.indexOf('{');
  if (start >= 0) {
    let depth = 0;
    let inString = false;
    let escaped = false;
    for (let i = start; i < cleaned.length; i += 1) {
      const char = cleaned[i];
      if (inString) {
        if (escaped) escaped = false;
        else if (char === '\\') escaped = true;
        else if (char === '"') inString = false;
        continue;
      }
      if (char === '"') inString = true;
      else if (char === '{') depth += 1;
      else if (char === '}') {
        depth -= 1;
        if (depth === 0) {
          candidates.push(cleaned.slice(start, i + 1));
          break;
        }
      }
    }
  }
  for (const candidate of candidates) {
    try {
      const parsed: unknown = JSON.parse(candidate);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) return parsed as JsonRecord;
    } catch {
      // Tenta o próximo trecho candidato.
    }
  }
  throw new Error('O leitor de IA respondeu fora do formato JSON esperado.');
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


const MAX_TEXT_PART_CHARACTERS = 14_000;
type ExtractedPage = { page_number: number; page_text: string };
type TextPart = { text: string; firstPage: number; lastPage: number };

function createTextParts(pages: ExtractedPage[]): TextPart[] {
  const usable = pages.filter((page) => page.page_text?.trim()).sort((a, b) => a.page_number - b.page_number);
  const result: TextPart[] = [];
  let blocks: string[] = [];
  let chars = 0;
  let firstPage = 0;
  let lastPage = 0;
  const flush = () => {
    if (!blocks.length) return;
    result.push({ text: blocks.join('\n\n'), firstPage, lastPage });
    blocks = [];
    chars = 0;
    firstPage = 0;
    lastPage = 0;
  };
  for (const page of usable) {
    const text = page.page_text.trim();
    for (let offset = 0; offset < text.length; offset += MAX_TEXT_PART_CHARACTERS) {
      const block = `PÁGINA ORIGINAL ${page.page_number}:\n${text.slice(offset, offset + MAX_TEXT_PART_CHARACTERS)}`;
      if (chars + block.length > MAX_TEXT_PART_CHARACTERS && blocks.length) flush();
      if (!firstPage) firstPage = page.page_number;
      lastPage = page.page_number;
      blocks.push(block);
      chars += block.length;
    }
  }
  flush();
  return result;
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

    const { data: extractedPages, error: extractedPagesError } = await supabase
      .from('document_extracted_pages')
      .select('page_number,page_text')
      .eq('source_document_id', id)
      .order('page_number', { ascending: true });
    if (extractedPagesError) {
      console.error('Falha ao consultar texto extraído no Supabase:', extractedPagesError.message);
      return NextResponse.json({ error: 'Não consegui acessar o texto extraído no Supabase. Tente novamente a leitura do PDF.' }, { status: 500 });
    }
    const pages = (extractedPages ?? []) as ExtractedPage[];
    const totalCharacters = pages.reduce((total, page) => total + (page.page_text?.trim().length ?? 0), 0);
    const pagesWithText = pages.filter((page) => page.page_text?.trim()).length;
    if (totalCharacters < 80 || pagesWithText === 0) {
      return NextResponse.json({
        error: 'O texto deste PDF ainda não foi extraído. Use o botão único “Ler PDF e cadastrar receitas” para fazer as duas etapas automaticamente.',
        code: 'PDF_TEXT_NOT_EXTRACTED',
      }, { status: 409 });
    }
    const textParts = createTextParts(pages);
    if (!textParts.length) {
      return NextResponse.json({ error: 'Não encontrei texto selecionável neste PDF. As páginas escaneadas precisam de OCR.', code: 'PDF_NO_SELECTABLE_TEXT' }, { status: 422 });
    }

    const promptInstructions = [
      'Você é um sistema de transcrição fiel de livros e apostilas culinárias para uma biblioteca de receitas em português brasileiro.',
      'Leia o texto extraído das páginas do PDF abaixo. Pode haver quebras de linha ou espaços estranhos.',
      'Use somente as informações presentes no texto. Não invente, estime, complete nem corrija ingredientes, quantidades, unidades, temperaturas, tempos, rendimento ou etapas.',
      'Se um dado não estiver legível ou não constar, use null ou deixe o campo ausente. Preserve quantidades ambíguas em quantity_text.',
      'Não misture receitas. Se uma receita estiver incompleta no trecho, omita-a. Só inclua receitas com ao menos um ingrediente e uma etapa de preparo.',
      'As páginas estão identificadas como PÁGINA ORIGINAL N. Todos os campos source_page, source_page_start e source_page_end devem usar exatamente esses números originais.',
      'Receitas que apareçam somente em páginas sem texto selecionável não devem ser inventadas nem completadas por suposição.',
      'Para cada receita retorne: title, original_title, original_language, description, difficulty (facil, media, dificil ou null), yield_text, prep_minutes, cook_minutes, bake_minutes, chill_minutes, rest_minutes, source_page_start, source_page_end, ingredients e steps.',
      'Cada ingrediente deve ter display_name, quantity, quantity_max, unit, quantity_text, preparation, is_optional, original_text e source_page.',
      'Cada etapa deve ter instruction, original_text, tip e source_page.',
      'Extraia também utensílios, ingredientes básicos, dicas e orientações em support_materials, com kind, title, body e source_page.',
      'Identifique o nome e a descrição da categoria em collection.name e collection.description.',
      'Responda somente com JSON válido, sem markdown, no formato: {"collection":{"name":"...","description":null},"recipes":[{"title":"...","ingredients":[{"display_name":"...","quantity":null,"quantity_max":null,"unit":null,"quantity_text":"...","preparation":null,"is_optional":false,"original_text":"...","source_page":1}],"steps":[{"instruction":"...","original_text":"...","tip":null,"source_page":1}]}],"support_materials":[{"kind":"dicas","title":"...","body":"...","source_page":1}]}',
    ].join('\n');

    const allRecipes: JsonRecord[] = [];
    const allSupportMaterials: JsonRecord[] = [];
    let collectionInfo: JsonRecord = {};

    const processTextPart = async (part: TextPart, partIndex: number): Promise<{ collection: JsonRecord; recipes: JsonRecord[]; supportMaterials: JsonRecord[] }> => {
      const prompt = [
        promptInstructions,
        `Trecho ${partIndex + 1} de ${textParts.length}. Páginas originais abrangidas: ${part.firstPage} a ${part.lastPage}.`,
        `Título do documento: ${document.title}.`,
        part.text,
      ].join('\n\n');

      const aiResponse = await fetch('https://openrouter.ai/api/v1/responses', {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          model: 'openrouter/free',
          max_output_tokens: 14000,
          text: { format: { type: 'json_object' } },
          input: [{ role: 'user', content: [{ type: 'input_text', text: prompt }] }],
        }),
        signal: AbortSignal.timeout(180_000),
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
        const providerError = aiPayload.error && typeof aiPayload.error === 'object' ? aiPayload.error as JsonRecord : {};
        const providerMessage = cleanText(providerError.message) ?? cleanText(aiPayload.message);
        console.error('OpenRouter text import failed:', {
          part: partIndex + 1, totalParts: textParts.length, status,
          message: providerMessage ?? 'Resposta sem mensagem de erro',
          responseExcerpt: providerMessage ? undefined : aiResponseText.slice(0, 1200),
        });
        const message = status === 401 ? 'A chave do OpenRouter não foi aceita. Confira o segredo cadastrado no cofre do Supabase.'
          : status === 402 ? 'O OpenRouter recusou a solicitação por limite ou saldo. Nenhuma receita foi cadastrada.'
          : status === 403 ? 'O OpenRouter não autorizou esta solicitação. Verifique as permissões da chave.'
          : status === 429 ? `O limite gratuito do OpenRouter foi atingido durante o trecho ${partIndex + 1} de ${textParts.length}. Nenhuma receita foi cadastrada; aguarde e tente novamente.`
          : status === 400 ? 'O OpenRouter rejeitou o texto extraído. O motivo técnico foi registrado; nenhuma receita foi cadastrada.'
          : 'O serviço gratuito de leitura não respondeu corretamente. Nenhuma receita foi cadastrada.';
        throw new Error(message);
      }

      const outputText = getOutputText(aiPayload);
      if (!outputText) {
        throw new Error(`A IA não retornou conteúdo legível no trecho ${partIndex + 1} de ${textParts.length}. Nenhuma receita foi cadastrada.`);
      }
      let parsed: JsonRecord;
      try {
        parsed = parseModelJson(outputText);
      } catch {
        // Alguns provedores gratuitos não respeitam o formato JSON na API
        // Responses. Tenta uma segunda vez pela API Chat Completions do
        // OpenRouter, que oferece response_format JSON amplamente suportado.
        console.warn('Resposta Responses inválida; tentando Chat Completions em JSON:', {
          part: partIndex + 1, totalParts: textParts.length,
        });
        try {
          const retryResponse = await fetch('https://openrouter.ai/api/v1/chat/completions', {
            method: 'POST',
            headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({
              model: 'openrouter/free',
              max_tokens: 12000,
              response_format: { type: 'json_object' },
              messages: [
                { role: 'system', content: promptInstructions },
                { role: 'user', content: [
                  `Trecho ${partIndex + 1} de ${textParts.length}. Páginas originais abrangidas: ${part.firstPage} a ${part.lastPage}.`,
                  `Título do documento: ${document.title}.`,
                  part.text,
                ].join('\\n\\n') },
              ],
            }),
            signal: AbortSignal.timeout(90_000),
          });
          const retryText = await retryResponse.text();
          let retryPayload: JsonRecord = {};
          try {
            const decoded: unknown = JSON.parse(retryText);
            if (decoded && typeof decoded === 'object' && !Array.isArray(decoded)) retryPayload = decoded as JsonRecord;
          } catch {
            // O erro final será tratado abaixo, sem gravar conteúdo parcial.
          }
          if (!retryResponse.ok) {
            const retryError = retryPayload.error && typeof retryPayload.error === 'object'
              ? retryPayload.error as JsonRecord : {};
            console.error('OpenRouter JSON retry failed:', {
              part: partIndex + 1, status: retryResponse.status,
              message: cleanText(retryError.message) ?? retryText.slice(0, 800),
            });
            throw new Error('A segunda tentativa de leitura também falhou.');
          }
          const choices = Array.isArray(retryPayload.choices) ? retryPayload.choices : [];
          const firstChoice = choices[0] && typeof choices[0] === 'object'
            ? choices[0] as JsonRecord : {};
          const message = firstChoice.message && typeof firstChoice.message === 'object'
            ? firstChoice.message as JsonRecord : {};
          const content = typeof message.content === 'string' ? message.content
            : Array.isArray(message.content)
              ? message.content.map((item) => item && typeof item === 'object'
                ? cleanText((item as JsonRecord).text) ?? '' : '').join('\\n')
              : '';
          if (!content.trim()) throw new Error('A segunda tentativa não retornou texto.');
          parsed = parseModelJson(content);
        } catch (retryError) {
          console.error('OpenRouter não conseguiu retornar JSON válido após nova tentativa:', {
            part: partIndex + 1, totalParts: textParts.length,
            message: retryError instanceof Error ? retryError.message : 'erro desconhecido',
          });
          throw new Error(`O leitor não conseguiu organizar o trecho ${partIndex + 1} de ${textParts.length}, mesmo após uma segunda tentativa. Nenhuma receita foi cadastrada.`);
        }
      }
      const normalized = normalizePayload(parsed);
      return {
        collection: normalized.collection && typeof normalized.collection === 'object' ? normalized.collection as JsonRecord : {},
        recipes: Array.isArray(normalized.recipes) ? normalized.recipes as JsonRecord[] : [],
        supportMaterials: Array.isArray(normalized.support_materials) ? normalized.support_materials as JsonRecord[] : [],
      };
    };

    let processedParts: Awaited<ReturnType<typeof processTextPart>>[];
    try {
      // Os trechos são independentes. Processá-los em paralelo evita exceder
      // o limite de 5 minutos da função quando o modelo gratuito está lento.
      processedParts = await Promise.all(textParts.map((part, index) => processTextPart(part, index)));
    } catch (partError) {
      const message = partError instanceof Error ? partError.message : 'Falha ao organizar o texto do PDF.';
      return NextResponse.json({ error: message, code: 'PDF_PART_PROCESSING_FAILED' }, { status: 502 });
    }

    for (const normalized of processedParts) {
      if (!collectionInfo.name && normalized.collection.name) collectionInfo = normalized.collection;
      allRecipes.push(...normalized.recipes);
      allSupportMaterials.push(...normalized.supportMaterials);
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

    return NextResponse.json({ result: imported, parts_processed: textParts.length, pages_read: pagesWithText, characters_read: totalCharacters }, { headers: { 'Cache-Control': 'no-store' } });
  } catch (error) {
    console.error('Falha na importação automática de PDF:', error instanceof Error ? error.message : 'erro desconhecido');
    return NextResponse.json({ error: 'Não foi possível concluir a leitura automática. Tente novamente.' }, { status: 500 });
  }
}
