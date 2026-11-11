import { NextResponse } from 'next/server';
import { APP_MODE } from '@/lib/env';
import { buildChefRequest, localChefAnswer, type ChefMessage } from '@/lib/chef';
import { askOpenAI, loadChefKnowledge } from '@/server/chef-knowledge';
import { createSupabaseServerClient, isUuid } from '@/server/supabase';

export const runtime = 'nodejs';
export const maxDuration = 60;

const DAILY_LIMIT = Math.max(1, Number(process.env.CHEF_DAILY_LIMIT ?? 30) || 30);
const fail = (status: number, code: string, message: string) => NextResponse.json({ error: code, message }, { status });

/**
 * Chef IA. Roda só no servidor: a chave da OpenAI nunca chega ao navegador.
 * A pessoa precisa estar logada e com acesso válido; há limite diário de perguntas;
 * as respostas usam exclusivamente as fichas publicadas que ela pode ler (RLS).
 */
export async function POST(request: Request) {
  if (APP_MODE !== 'supabase') return fail(404, 'not_found', 'Indisponível neste modo.');

  const body = (await request.json().catch(() => null)) as { message?: unknown; conversationId?: unknown; recipeId?: unknown } | null;
  const message = typeof body?.message === 'string' ? body.message.trim() : '';
  if (!message || message.length > 1000) return fail(400, 'invalid_message', 'Escreva uma pergunta de até 1000 caracteres.');
  const recipeId = isUuid(body?.recipeId) ? body.recipeId : null;

  const supabase = await createSupabaseServerClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) return fail(401, 'not_authenticated', 'Entre na sua conta para conversar com o Chef.');

  const { data: access, error: accessError } = await supabase.rpc('my_access');
  if (accessError) {
    console.error('[chef] falha ao verificar o acesso:', accessError.code, accessError.message);
    return fail(500, 'access_check_failed', 'Não foi possível verificar seu acesso.');
  }
  if (!access?.has_access) return fail(403, 'access_required', 'O Chef IA faz parte do acesso da temporada.');

  const since = new Date(Date.now() - 86_400_000).toISOString();
  const { count, error: countError } = await supabase.from('ai_messages').select('id', { count: 'exact', head: true }).eq('role', 'user').gte('created_at', since);
  if (countError) {
    console.error('[chef] falha ao verificar o limite de uso:', countError.code, countError.message);
    return fail(500, 'usage_check_failed', 'Não foi possível verificar o limite de uso.');
  }
  if ((count ?? 0) >= DAILY_LIMIT) return fail(429, 'limit_reached', `Você atingiu o limite de ${DAILY_LIMIT} perguntas em 24 horas.`);

  // conversa (o RLS garante que só a dona enxerga)
  let conversationId = isUuid(body?.conversationId) ? body.conversationId : null;
  let history: ChefMessage[] = [];
  if (conversationId) {
    const { data: rows } = await supabase.from('ai_messages').select('role, content').eq('conversation_id', conversationId).order('created_at', { ascending: false }).limit(8);
    const { data: owned } = await supabase.from('ai_conversations').select('id').eq('id', conversationId).maybeSingle();
    if (!owned) conversationId = null;
    else history = ((rows ?? []) as ChefMessage[]).reverse();
  }
  if (!conversationId) {
    const { data: created, error } = await supabase.from('ai_conversations').insert({ title: message.slice(0, 60), recipe_id: recipeId }).select('id').single();
    if (error || !created) {
      console.error('[chef] falha ao iniciar a conversa:', error?.code, error?.message);
      return fail(500, 'conversation_failed', 'Não foi possível iniciar a conversa.');
    }
    conversationId = created.id as string;
  }

  let knowledge;
  try {
    knowledge = await loadChefKnowledge(supabase, message, recipeId);
  } catch (error) {
    console.error('[chef] falha ao consultar as fichas:', (error as Error).message);
    return fail(500, 'knowledge_failed', 'Não foi possível consultar as fichas agora.');
  }

  let answer: string;
  let model = 'local';
  let tokensIn: number | null = null;
  let tokensOut: number | null = null;
  const grounded = knowledge.relevant.map((d) => d.recipe);

  if (process.env.OPENAI_API_KEY && knowledge.recipes.length) {
    try {
      const result = await askOpenAI(buildChefRequest(message, history, knowledge.relevant, knowledge.availableTitles));
      ({ text: answer, model, tokensIn, tokensOut } = result);
    } catch (error) {
      console.error('[chef] falha na OpenAI, usando consulta direta à ficha:', (error as Error).message);
      answer = localChefAnswer(message, knowledge.relevant, recipeId).answer;
    }
  } else {
    answer = localChefAnswer(message, knowledge.relevant, recipeId).answer;
  }

  // As duas linhas têm colunas diferentes: sem defaultToNull: false o PostgREST gravaria NULL nas colunas
  // ausentes da pergunta (grounded_recipe_ids é NOT NULL com valor padrão) e recusaria o lote inteiro.
  const { error: saveError } = await supabase.from('ai_messages').insert(
    [
      { conversation_id: conversationId, role: 'user', content: message },
      { conversation_id: conversationId, role: 'assistant', content: answer, grounded_recipe_ids: grounded.map((r) => r.id), model, tokens_in: tokensIn, tokens_out: tokensOut },
    ],
    { defaultToNull: false },
  );
  if (saveError) {
    console.error('[chef] falha ao salvar a conversa:', saveError.code, saveError.message);
    return fail(500, 'save_failed', 'Não foi possível salvar a conversa.');
  }
  await supabase.rpc('refresh_my_challenges');

  return NextResponse.json({
    answer,
    conversationId,
    model,
    grounded: grounded.map((r) => ({ id: r.id, title: r.title, slug: r.slug })),
    remaining: Math.max(0, DAILY_LIMIT - (count ?? 0) - 1),
  });
}
