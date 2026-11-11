import { describe, expect, it } from 'vitest';
import { buildSchedule, daysUntil, defaultTaskDueDate, DEFAULT_TASKS } from '@/lib/schedule';
import { addTime, createTimer, pauseTimer, progress, remainingMs, restartTimer, resumeTimer, sanitizeTimers, tick } from '@/lib/timers';
import { computeProgress, refreshChallenges, totalPoints, type ChallengeFacts } from '@/lib/challenges';
import { buildChefRequest, CHEF_SYSTEM_PROMPT, isOffTopic, localChefAnswer, recipeToContext, requestedFactor, selectRelevant } from '@/lib/chef';
import { buildManifest, centsFromAmount, parseSignatureHeader, signManifest, verifyWebhookSignature } from '@/lib/mercadopago';
import { saleAvailability } from '@/lib/season';
import { createHmac } from 'node:crypto';
import type { Challenge } from '@/lib/types';
import { pave, tables } from './fixtures';

const hhmm = (d: Date) => `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')} ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;

describe('cronograma da ceia', () => {
  const input = { eventDate: '2026-12-24', serveTime: '20:00', blockMinutes: 30, recipes: [{ detail: pave(), factor: 1 }] };

  it('calcula de trás para frente usando só os tempos da ficha + blocos de organização', () => {
    const schedule = buildSchedule(input);
    expect(hhmm(schedule.serveAt)).toBe('24/12 20:00');
    const start = schedule.entries.find((e) => e.kind === 'start')!;
    // 3 blocos de 30 min + 4 min de fogo + 6 h de geladeira = 7 h 34 min antes de servir
    expect(hhmm(start.at)).toBe('24/12 12:26');
    expect(start.estimated).toBe(true);
    expect(start.detail).toContain('4 min de fogo/forno');
    expect(start.detail).toContain('6 h de geladeira/descanso');
    expect(start.detail).toContain('estimativa sua');
    const wait = schedule.entries.find((e) => e.kind === 'wait')!;
    // a espera de 6 h precisa começar 6 h + 2 blocos (montagem e preparo) antes de servir
    expect(hhmm(wait.at)).toBe('24/12 13:00');
    expect(wait.detail).toContain('Mínimo de 6 h');
    expect(schedule.entries.map((e) => e.kind)).toEqual(['start', 'wait', 'serve']);
  });

  it('sem bloco de organização, usa exclusivamente os tempos cadastrados', () => {
    const schedule = buildSchedule({ ...input, blockMinutes: 0 });
    const start = schedule.entries.find((e) => e.kind === 'start')!;
    expect(hhmm(start.at)).toBe('24/12 13:56');
    expect(start.estimated).toBe(false);
  });

  it('avança para a véspera quando o preparo não cabe no dia', () => {
    const schedule = buildSchedule({ ...input, serveTime: '06:00' });
    expect(hhmm(schedule.entries[0].at)).toBe('23/12 22:26');
  });

  it('receita sem ficha disponível não recebe horários inventados', () => {
    const empty = { ...pave(), parts: [], hasContent: false };
    const schedule = buildSchedule({ ...input, recipes: [{ detail: empty, factor: 1 }] });
    expect(schedule.withoutTimes).toEqual(['Pavê Floresta Negra com Creme Danete']);
    expect(schedule.entries.map((e) => e.kind)).toEqual(['serve']);
  });

  it('gera o checklist padrão com datas relativas ao evento', () => {
    expect(DEFAULT_TASKS).toHaveLength(6);
    expect(defaultTaskDueDate('2026-12-24', 7).slice(0, 10)).toBe('2026-12-17');
    expect(defaultTaskDueDate('2027-01-01', 2).slice(0, 10)).toBe('2026-12-30');
    expect(daysUntil('2026-12-24', new Date(2026, 10, 10, 15))).toBe(44);
  });
});

describe('temporizadores', () => {
  const t0 = 1_000_000;
  const base = () => createTimer({ label: 'Mexer após ferver', durationMs: 240_000 }, t0, 't1');

  it('continua correto mesmo que a tela fique fechada (usa o horário de término)', () => {
    const timer = base();
    expect(remainingMs(timer, t0 + 60_000)).toBe(180_000);
    expect(remainingMs(timer, t0 + 10 * 60_000)).toBe(0);
    const { timers, finished } = tick([timer], t0 + 10 * 60_000);
    expect(timers[0].status).toBe('done');
    expect(timers[0].finishedAt).toBe(t0 + 240_000);
    expect(finished).toHaveLength(1);
    expect(tick(timers, t0 + 11 * 60_000).finished).toHaveLength(0); // não avisa duas vezes
  });

  it('pausa, retoma, reinicia e acrescenta tempo', () => {
    let timer = pauseTimer(base(), t0 + 100_000);
    expect(timer).toMatchObject({ status: 'paused', remainingMs: 140_000, endsAt: null });
    expect(remainingMs(timer, t0 + 999_000)).toBe(140_000);
    timer = resumeTimer(timer, t0 + 500_000);
    expect(timer.endsAt).toBe(t0 + 640_000);
    expect(progress(timer, t0 + 570_000)).toBeCloseTo(0.708, 2);
    timer = addTime(timer, 60_000, t0 + 570_000);
    expect(remainingMs(timer, t0 + 570_000)).toBe(130_000);
    timer = restartTimer(timer, t0 + 600_000);
    expect(remainingMs(timer, t0 + 600_000)).toBe(300_000);
  });

  it('descarta dados inválidos do armazenamento local', () => {
    expect(sanitizeTimers('x')).toEqual([]);
    expect(sanitizeTimers([{ id: 1 }, null, base()])).toHaveLength(1);
  });
});

describe('desafios', () => {
  const challenges = tables('challenges') as Challenge[];
  const paves = pave();
  const facts = (over: Partial<ChallengeFacts> = {}): ChallengeFacts => ({
    sessions: [], collectionSlugByRecipe: new Map([[paves.recipe.id, 'paves'], ['p1', 'panetones-chocotones']]), plans: [], planRecipes: [],
    planTasks: [], lists: [], items: [], favorites: [], userMessages: 0, ...over,
  });
  const bySlug = (slug: string) => challenges.find((c) => c.slug === slug)!;

  it('conta receitas diferentes concluídas, por coleção quando o desafio pede', () => {
    const f = facts({ sessions: [{ recipe_id: paves.recipe.id, status: 'finished' }, { recipe_id: paves.recipe.id, status: 'finished' }, { recipe_id: 'p1', status: 'active' }] });
    expect(computeProgress(bySlug('sobremesa-especial'), f)).toBe(1);
    expect(computeProgress(bySlug('tres-receitas'), f)).toBe(1);
    expect(computeProgress(bySlug('primeiro-panetone'), f)).toBe(0);
    expect(computeProgress(bySlug('primeiro-panetone'), facts({ sessions: [{ recipe_id: 'p1', status: 'finished' }] }))).toBe(1);
  });

  it('planejamento, compras, favoritas e chef', () => {
    const f = facts({
      plans: [{ id: 'a', event_date: '2026-12-24' }, { id: 'b', event_date: null }],
      planRecipes: [{ plan_id: 'a' }, { plan_id: 'b' }],
      planTasks: [{ plan_id: 'a', is_done: true }, { plan_id: 'a', is_done: true }, { plan_id: 'b', is_done: false }],
      lists: [{ id: 'l' }],
      items: Array.from({ length: 5 }, () => ({ list_id: 'l', is_checked: true })),
      favorites: [{ recipe_id: '1' }, { recipe_id: '2' }],
      userMessages: 4,
    });
    expect(computeProgress(bySlug('organize-sua-ceia'), f)).toBe(1);
    expect(computeProgress(bySlug('conclua-seu-planejamento'), f)).toBe(1);
    expect(computeProgress(bySlug('organize-as-compras'), f)).toBe(1);
    expect(computeProgress(bySlug('organize-as-compras'), { ...f, items: f.items.slice(1) })).toBe(0); // menos de 5 itens
    expect(computeProgress(bySlug('salve-suas-favoritas'), f)).toBe(2);
    expect(computeProgress(bySlug('converse-com-o-chef'), f)).toBe(4);
  });

  it('concede pontos ao concluir e nunca retira uma conquista', () => {
    const now = new Date('2026-12-20T12:00:00Z');
    const first = refreshChallenges(challenges, [], facts({ sessions: [{ recipe_id: paves.recipe.id, status: 'finished' }], userMessages: 9 }), now);
    expect(first).toHaveLength(9);
    const done = first.filter((p) => p.completed_at);
    expect(done.map((p) => bySlug_(p.challenge_id)).sort()).toEqual(['converse-com-o-chef', 'sobremesa-especial']);
    expect(totalPoints(first)).toBe(30);
    expect(first.find((p) => p.challenge_id === bySlug('converse-com-o-chef').id)).toMatchObject({ progress: 1, target: 1 }); // limitado ao alvo
    const later = refreshChallenges(challenges, first, facts(), new Date('2026-12-21T12:00:00Z'));
    expect(totalPoints(later)).toBe(30);
    expect(later.find((p) => p.challenge_id === bySlug('sobremesa-especial').id)?.completed_at).toBe(now.toISOString());
    function bySlug_(id: string) { return challenges.find((c) => c.id === id)!.slug; }
  });
});

describe('chef ia (base nas fichas aprovadas)', () => {
  const recipes = [pave()];

  it('o contexto enviado ao modelo contém a ficha com quantidades, tempos e páginas', () => {
    const context = recipeToContext(recipes[0]);
    expect(context).toContain('### Pavê Floresta Negra com Creme Danete');
    expect(context).toContain('- 600 g — leite condensado (1 lata e meia) [p. 4]');
    expect(context).toContain('Porções: não informado no material');
    expect(context).toContain('Geladeira — creme danete: mínimo 6 h');
    expect(context).toContain('- quantidade não informada — granulé');
    const request = buildChefRequest('Como faço o creme?', [], recipes, ['Pavê Floresta Negra com Creme Danete']);
    expect(request.instructions.startsWith(CHEF_SYSTEM_PROMPT)).toBe(true);
    expect(request.instructions).toContain('NÃO faz parte da receita original');
    expect(request.input.at(-1)).toEqual({ role: 'user', content: 'Como faço o creme?' });
  });

  it('seleciona fichas pela pergunta e não força uma receita quando nada corresponde', () => {
    expect(selectRelevant('como faço o pavê floresta negra?', recipes)).toHaveLength(1);
    expect(selectRelevant('tem cereja em alguma receita?', recipes)).toHaveLength(1);
    expect(selectRelevant('como assar um peru?', recipes)).toHaveLength(0);
    expect(selectRelevant('qualquer coisa', recipes, { focusRecipeId: recipes[0].recipe.id })).toHaveLength(1);
  });

  it('diz quando a informação não está disponível, sem inventar', () => {
    const none = localChefAnswer('Como assar um peru de 5 kg?', recipes);
    expect(none.groundedRecipeIds).toEqual([]);
    expect(none.answer).toContain('Não encontrei essa informação nas fichas aprovadas');
    const freeze = localChefAnswer('Posso congelar o pavê?', recipes);
    expect(freeze.answer).toContain('não informa prazo de validade, congelamento');
    expect(freeze.answer).toContain('não é parte da receita');
    const oven = localChefAnswer('Qual a temperatura do forno do pavê?', recipes);
    expect(oven.answer).toContain('não informa temperatura');
    expect(localChefAnswer('oi', []).answer).toContain('Ainda não há fichas aprovadas');
  });

  it('com uma receita aberta, não responde sobre assunto que não está na ficha', () => {
    const focus = recipes[0].recipe.id;
    const off = localChefAnswer('Como faço um peru assado?', recipes, focus);
    expect(off.groundedRecipeIds).toEqual([]);
    expect(off.answer).toContain('Não encontrei essa informação nas fichas aprovadas');
    // perguntas genéricas ou sobre algo citado na ficha continuam usando a receita aberta
    expect(localChefAnswer('Posso congelar?', recipes, focus).groundedRecipeIds).toEqual([focus]);
    expect(localChefAnswer('Quanto tempo de geladeira?', recipes, focus).answer).toContain('mínimo de 6 h');
    expect(localChefAnswer('Como faço o chantilly?', recipes, focus).groundedRecipeIds).toEqual([focus]);
    expect(localChefAnswer('Posso trocar as cerejas por morangos?', recipes, focus).answer).toContain('NÃO faz parte da receita original');
    expect(isOffTopic('Quais os ingredientes?', recipes[0])).toBe(false);
    expect(isOffTopic('E a farofa?', recipes[0])).toBe(true);
  });

  it('deixa claro quando uma substituição não é da receita original', () => {
    const { answer, groundedRecipeIds } = localChefAnswer('Posso trocar o leite condensado do pavê por doce de leite?', recipes);
    expect(answer).toContain('NÃO faz parte da receita original');
    expect(answer).toContain('600 g de leite condensado');
    expect(groundedRecipeIds).toEqual([recipes[0].recipe.id]);
    // cita só o ingrediente perguntado (creme de leite), não todos os que têm "leite" no nome
    const cream = localChefAnswer('Posso trocar o creme de leite por iogurte?', recipes).answer;
    expect(cream).toContain('o ingrediente original é: 400 g de creme de leite.');
  });

  it('responde ingredientes, preparo e tempos a partir da ficha, citando a fonte', () => {
    const ingredients = localChefAnswer('Quais os ingredientes do pavê?', recipes).answer;
    expect(ingredients).toContain('• 400 g de creme de leite');
    expect(ingredients).toContain('• quantidade não informada: granulé');
    expect(ingredients).toContain('Fonte: ficha “Pavê Floresta Negra com Creme Danete” (p. 4–8).');
    const steps = localChefAnswer('Como é a montagem do pavê?', recipes).answer;
    expect(steps).toContain('1. 1ª camada: creme danete.');
    expect(steps).not.toContain('Dilua o chocolate'); // só a parte pedida
    const times = localChefAnswer('Quanto tempo de geladeira o pavê precisa?', recipes).answer;
    expect(times).toContain('mínimo de 6 h');
    expect(times).toContain('não informa o tempo total de preparo');
  });

  it('ajusta porções sem converter unidades e recusa calcular por pessoas sem dado de porções', () => {
    expect(requestedFactor('quero dobrar a receita', recipes[0])).toEqual({ factor: 2, reason: null });
    expect(requestedFactor('fazer 3 travessas', recipes[0]).factor).toBe(3);
    const doubled = localChefAnswer('Quero dobrar o pavê', recipes).answer;
    expect(doubled).toContain('2 travessas de 27 × 17 cm');
    expect(doubled).toContain('• 1.200 g de leite condensado');
    expect(doubled).toContain('• 2 pacotes de bolacha champanhe (validar na prática)');
    expect(doubled).toContain('sem converter unidades');
    const people = localChefAnswer('Pavê para 30 pessoas, quanto de cada ingrediente?', recipes).answer;
    expect(people).toContain('não informa quantas porções');
    expect(people).not.toContain('• ');
  });
});

describe('mercado pago', () => {
  const secret = 'segredo-do-painel';
  const ts = '1742505638683';
  const requestId = 'bb56a2f1-6aae-46ac-982e-9dcd3581d08e';
  // referência independente, montada à mão conforme a documentação
  const reference = createHmac('sha256', secret).update(`id:123456;request-id:${requestId};ts:${ts};`).digest('hex');

  it('monta o manifesto conforme a documentação', () => {
    expect(buildManifest({ dataId: '123456', requestId, ts })).toBe(`id:123456;request-id:${requestId};ts:${ts};`);
    expect(buildManifest({ dataId: 'ABC123', requestId: null, ts })).toBe(`id:abc123;ts:${ts};`);
    expect(signManifest(`id:123456;request-id:${requestId};ts:${ts};`, secret)).toBe(reference);
  });

  it('aceita assinatura válida e rejeita qualquer alteração', () => {
    const header = `ts=${ts},v1=${reference}`;
    const ok = { signatureHeader: header, requestId, dataId: '123456', secret };
    expect(verifyWebhookSignature(ok)).toBe(true);
    expect(verifyWebhookSignature({ ...ok, dataId: '123457' })).toBe(false);
    expect(verifyWebhookSignature({ ...ok, requestId: 'outro' })).toBe(false);
    expect(verifyWebhookSignature({ ...ok, secret: 'errado' })).toBe(false);
    expect(verifyWebhookSignature({ ...ok, secret: '' })).toBe(false);
    expect(verifyWebhookSignature({ ...ok, signatureHeader: `ts=${ts}1,v1=${reference}` })).toBe(false);
    expect(verifyWebhookSignature({ ...ok, signatureHeader: null })).toBe(false);
    expect(verifyWebhookSignature({ ...ok, signatureHeader: 'v1=abc' })).toBe(false);
    expect(parseSignatureHeader(` ts=${ts} , v1=${reference.toUpperCase()} `)).toEqual({ ts, v1: reference });
  });

  it('converte valores sem erro de ponto flutuante', () => {
    expect(centsFromAmount(49.9)).toBe(4990);
    expect(centsFromAmount(19.99)).toBe(1999);
    expect(centsFromAmount(0.07)).toBe(7);
  });

  it('só abre a venda com temporada ativa, preço definido e dentro do período', () => {
    const season = { status: 'active', price_cents: 4990, sales_starts_at: '2026-11-01T03:00:00Z', sales_ends_at: '2027-01-01T02:59:59Z' };
    const now = new Date('2026-11-10T12:00:00Z');
    expect(saleAvailability(season, now)).toEqual({ open: true, reason: null });
    expect(saleAvailability({ ...season, status: 'draft' }, now).open).toBe(false);
    expect(saleAvailability({ ...season, price_cents: null }, now).reason).toContain('valor');
    expect(saleAvailability(season, new Date('2026-10-01T00:00:00Z')).reason).toContain('ainda não começaram');
    expect(saleAvailability(season, new Date('2027-01-02T00:00:00Z')).reason).toContain('encerradas');
    expect(saleAvailability(null, now).open).toBe(false);
  });
});
