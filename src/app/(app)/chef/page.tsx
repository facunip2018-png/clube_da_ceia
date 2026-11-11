'use client';

import { useSearchParams } from 'next/navigation';
import { Suspense, useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { BookOpen, ChefHat, Plus, Send } from 'lucide-react';
import { invalidate, useCatalog, useRecipeDetails, useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { Guard } from '@/components/gates';
import { useToast } from '@/components/toast';
import { Notice, PageHead, usePageTitle } from '@/components/ui';
import { localChefAnswer } from '@/lib/chef';
import type { AiMessage } from '@/lib/types';

const DAILY_LIMIT = 30;
const WELCOME =
  'Olá! Sou o Chef da Ceia. Respondo com base nas fichas aprovadas do Clube: ingredientes, modo de preparo, tempos, rendimento e ajuste de porções. Quando uma informação não estiver na ficha, eu aviso — não invento.';

interface ChefReply {
  answer: string;
  conversationId: string;
  model: string;
  grounded: { id: string; title: string; slug: string }[];
}

function Chat() {
  const params = useSearchParams();
  const focusSlug = params.get('receita');
  const { store, mode } = useSession();
  const { fail } = useToast();
  const { recipes } = useCatalog();
  const published = useMemo(() => recipes.filter((r) => r.status === 'published'), [recipes]);
  const focus = published.find((r) => r.slug === focusSlug) ?? null;
  // No modo demonstração o Chef responde no próprio navegador, só com o que este perfil pode ler.
  const { details } = useRecipeDetails(mode === 'demo' ? published : []);

  const { rows: conversations } = useTable('ai_conversations', { eq: { archived_at: null }, order: [['created_at', 'desc']], limit: 1 });
  const conversation = conversations?.[0] ?? null;
  const { rows: stored } = useTable('ai_messages', conversation ? { eq: { conversation_id: conversation.id }, order: [['created_at', 'asc']] } : null);
  const { rows: recent } = useTable('ai_messages', { eq: { role: 'user' }, order: [['created_at', 'desc']], limit: DAILY_LIMIT + 5 });

  const [pending, setPending] = useState<string | null>(null);
  const [text, setText] = useState('');
  const [limitHit, setLimitHit] = useState(false);
  const scroller = useRef<HTMLDivElement>(null);
  const usedToday = useMemo(() => (recent ?? []).filter((m) => Date.now() - new Date(m.created_at).getTime() < 86_400_000).length, [recent]);
  const messages: Pick<AiMessage, 'id' | 'role' | 'content' | 'model' | 'grounded_recipe_ids'>[] = stored ?? [];

  // rola apenas a área de mensagens (não a página inteira)
  useEffect(() => {
    const box = scroller.current;
    if (box) box.scrollTop = box.scrollHeight;
  }, [messages.length, pending]);

  const suggestions = useMemo(() => {
    const target = focus ?? published.find((r) => r.content_state === 'structured');
    if (!target) return [];
    const short = target.title.split(' com ')[0];
    return [`Quais os ingredientes do ${short}?`, `Quanto tempo o ${short} precisa de geladeira?`, `Quero dobrar a receita do ${short}`, `Posso congelar o ${short}?`];
  }, [focus, published]);

  async function ask(question: string) {
    const content = question.trim();
    if (!content || pending) return;
    if (usedToday >= DAILY_LIMIT) return setLimitHit(true);
    setPending(content);
    setText('');
    try {
      if (mode === 'demo') {
        let conversationId = conversation?.id;
        if (!conversationId) {
          const [created] = await store.insert('ai_conversations', { title: content.slice(0, 60), recipe_id: focus?.id ?? null });
          conversationId = created.id;
        }
        const reply = localChefAnswer(content, details.filter((d) => d.hasContent), focus?.id);
        await store.insert('ai_messages', { conversation_id: conversationId, role: 'user', content });
        await store.insert('ai_messages', { conversation_id: conversationId, role: 'assistant', content: reply.answer, grounded_recipe_ids: reply.groundedRecipeIds, model: 'local' });
        await store.rpc('refresh_my_challenges').catch(() => undefined);
      } else {
        const response = await fetch('/api/chef', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ message: content, conversationId: conversation?.id ?? null, recipeId: focus?.id ?? null }),
        });
        const data = (await response.json().catch(() => ({}))) as Partial<ChefReply> & { message?: string };
        if (response.status === 429) setLimitHit(true);
        if (!response.ok) throw new Error(data.message ?? 'O Chef não conseguiu responder agora. Tente novamente em instantes.');
      }
      await invalidate('ai_conversations', 'ai_messages', 'refresh_my_challenges');
    } catch (error) {
      fail(error);
      setText(content);
    } finally {
      setPending(null);
    }
  }

  async function newConversation() {
    if (!conversation) return;
    try {
      await store.update('ai_conversations', { id: conversation.id }, { archived_at: new Date().toISOString() });
      await invalidate('ai_conversations', 'ai_messages');
    } catch (error) {
      fail(error);
    }
  }

  const titleOf = (id: string) => recipes.find((r) => r.id === id)?.title;

  return (
    <>
      <div className="chat">
        <div className="chathead">
          <div className="chefmark"><ChefHat /></div>
          <div className="grow">
            <b className="serif" style={{ fontSize: 18 }}>Chef da Ceia</b>
            <div style={{ fontSize: 12.5, color: '#c9d6cb' }}>{focus ? `Falando sobre: ${focus.title}` : 'Responde com base nas fichas aprovadas'}</div>
          </div>
          {messages.length > 0 && <button type="button" className="btn sm" style={{ background: '#ffffff18', color: '#fff' }} onClick={newConversation}><Plus /> Nova conversa</button>}
        </div>
        <div className="messages" aria-live="polite" ref={scroller}>
          <div className="bubble bot">{WELCOME}</div>
          {messages.map((message) => (
            <div key={message.id} className={`bubble ${message.role === 'user' ? 'user' : 'bot'}`}>
              {message.content}
              {message.role === 'assistant' && (message.grounded_recipe_ids.length > 0 || message.model === 'local') && (
                <div className="meta">
                  {message.grounded_recipe_ids.map((id) => titleOf(id) && <span key={id} className="pill gold"><BookOpen /> {titleOf(id)}</span>)}
                  {message.model === 'local' && <span className="pill muted">consulta direta à ficha · sem IA generativa</span>}
                </div>
              )}
            </div>
          ))}
          {pending && (
            <>
              <div className="bubble user">{pending}</div>
              <div className="bubble bot"><span className="typing" aria-label="O Chef está escrevendo"><i /><i /><i /></span></div>
            </>
          )}
        </div>
        {suggestions.length > 0 && messages.length === 0 && !pending && (
          <div className="quick">{suggestions.map((s) => <button key={s} type="button" onClick={() => ask(s)}>{s}</button>)}</div>
        )}
        <form className="compose" onSubmit={(event: FormEvent) => { event.preventDefault(); void ask(text); }}>
          <input value={text} onChange={(e) => setText(e.target.value)} placeholder="Escreva sua pergunta…" aria-label="Sua pergunta" maxLength={1000} disabled={Boolean(pending)} />
          <button type="submit" className="btn dark" disabled={!text.trim() || Boolean(pending)}><Send /> <span className="sr-only">Enviar</span></button>
        </form>
      </div>
      <div style={{ maxWidth: 820, margin: '14px auto 0' }} className="stack">
        {limitHit && <Notice tone="danger">Você atingiu o limite de {DAILY_LIMIT} perguntas em 24 horas. Volte amanhã — as fichas continuam disponíveis nas coleções.</Notice>}
        {!published.length && <Notice>Ainda não há fichas publicadas. O Chef passa a responder assim que as primeiras receitas forem aprovadas.</Notice>}
        <p className="muted small center">
          {usedToday}/{DAILY_LIMIT} perguntas nas últimas 24 h · O Chef não substitui a leitura da ficha. Substituições de ingredientes não fazem parte das receitas originais.
        </p>
      </div>
    </>
  );
}

export default function ChefPage() {
  usePageTitle('Chef IA');
  return (
    <>
      <PageHead eyebrow="Uma ajuda na ponta dos dedos" title="Converse com o Chef." sub="Tire dúvidas sobre as receitas do Clube: ingredientes, preparo, tempos e ajuste de porções." />
      <Guard access what="O Chef IA">
        <Suspense>
          <Chat />
        </Suspense>
      </Guard>
    </>
  );
}
