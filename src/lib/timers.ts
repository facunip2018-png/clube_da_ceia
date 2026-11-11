/**
 * Temporizadores globais. O estado guarda o horário absoluto de término,
 * por isso continua correto ao trocar de tela, recarregar ou voltar ao app.
 */
export interface KitchenTimer {
  id: string;
  label: string;
  durationMs: number;
  /** horário (epoch ms) em que termina, quando está rodando */
  endsAt: number | null;
  /** tempo restante guardado ao pausar */
  remainingMs: number;
  status: 'running' | 'paused' | 'done';
  recipeId?: string | null;
  recipeTitle?: string | null;
  recipeSlug?: string | null;
  stepId?: string | null;
  sourceTimerId?: string | null;
  isMinimum?: boolean;
  createdAt: number;
  finishedAt?: number | null;
  acknowledged?: boolean;
}

export type NewTimer = Pick<KitchenTimer, 'label' | 'durationMs'> &
  Partial<Pick<KitchenTimer, 'recipeId' | 'recipeTitle' | 'recipeSlug' | 'stepId' | 'sourceTimerId' | 'isMinimum'>>;

export function createTimer(input: NewTimer, now: number, id: string): KitchenTimer {
  return { ...input, id, endsAt: now + input.durationMs, remainingMs: input.durationMs, status: 'running', createdAt: now, finishedAt: null, acknowledged: false };
}

export function remainingMs(timer: KitchenTimer, now: number): number {
  if (timer.status === 'running' && timer.endsAt != null) return Math.max(0, timer.endsAt - now);
  if (timer.status === 'done') return 0;
  return timer.remainingMs;
}

export function pauseTimer(timer: KitchenTimer, now: number): KitchenTimer {
  if (timer.status !== 'running') return timer;
  return { ...timer, status: 'paused', remainingMs: remainingMs(timer, now), endsAt: null };
}

export function resumeTimer(timer: KitchenTimer, now: number): KitchenTimer {
  if (timer.status !== 'paused') return timer;
  return { ...timer, status: 'running', endsAt: now + timer.remainingMs };
}

export function restartTimer(timer: KitchenTimer, now: number): KitchenTimer {
  return { ...timer, status: 'running', endsAt: now + timer.durationMs, remainingMs: timer.durationMs, finishedAt: null, acknowledged: false };
}

export function addTime(timer: KitchenTimer, extraMs: number, now: number): KitchenTimer {
  if (timer.status === 'running' && timer.endsAt != null) return { ...timer, endsAt: timer.endsAt + extraMs, durationMs: timer.durationMs + extraMs };
  if (timer.status === 'paused') return { ...timer, remainingMs: timer.remainingMs + extraMs, durationMs: timer.durationMs + extraMs };
  return { ...timer, status: 'running', endsAt: now + extraMs, remainingMs: extraMs, finishedAt: null, acknowledged: false };
}

/** Marca como concluídos os temporizadores que venceram. Devolve também os que acabaram de terminar. */
export function tick(timers: KitchenTimer[], now: number): { timers: KitchenTimer[]; finished: KitchenTimer[] } {
  const finished: KitchenTimer[] = [];
  let changed = false;
  const next = timers.map((timer) => {
    if (timer.status === 'running' && timer.endsAt != null && timer.endsAt <= now) {
      const done: KitchenTimer = { ...timer, status: 'done', remainingMs: 0, finishedAt: timer.endsAt, endsAt: null };
      finished.push(done);
      changed = true;
      return done;
    }
    return timer;
  });
  return { timers: changed ? next : timers, finished };
}

export function progress(timer: KitchenTimer, now: number): number {
  if (timer.durationMs <= 0) return 1;
  return Math.min(1, Math.max(0, 1 - remainingMs(timer, now) / timer.durationMs));
}

export const TIMER_PRESETS_MINUTES = [5, 10, 20, 30];

/** Garante que o que veio do armazenamento local tem o formato esperado. */
export function sanitizeTimers(value: unknown): KitchenTimer[] {
  if (!Array.isArray(value)) return [];
  return value.filter(
    (t): t is KitchenTimer =>
      Boolean(t) && typeof t.id === 'string' && typeof t.label === 'string' && typeof t.durationMs === 'number' &&
      ['running', 'paused', 'done'].includes(t.status) && typeof t.remainingMs === 'number',
  );
}
