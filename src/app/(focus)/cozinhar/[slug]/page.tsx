'use client';

import Link from 'next/link';
import { useParams, useRouter, useSearchParams } from 'next/navigation';
import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ALargeSmall, ArrowLeft, ArrowRight, Check, Pause, Play, RotateCcw, Timer, Trophy, X } from 'lucide-react';
import { useRecipeDetail, useTable, invalidate } from '@/data/hooks';
import { useSession } from '@/data/session';
import { finishCookingSession } from '@/data/actions';
import { Paywall } from '@/components/gates';
import { useTimers } from '@/components/timers';
import { useToast } from '@/components/toast';
import { flattenSteps } from '@/lib/recipe-view';
import { clampFactor, describeYield, scaleIngredient } from '@/lib/scaling';
import { formatClock, formatDuration } from '@/lib/format';
import { remainingMs } from '@/lib/timers';
import { safeStorage } from '@/lib/safe-storage';
import type { CookingSession, RecipeDetail, RecipeStepTimer } from '@/lib/types';

/** Mantém a tela acesa enquanto a pessoa cozinha (quando o navegador permite). */
function useWakeLock() {
  useEffect(() => {
    let lock: { release: () => Promise<void> } | null = null;
    let cancelled = false;
    const request = async () => {
      try {
        const wakeLock = (navigator as Navigator & { wakeLock?: { request: (type: 'screen') => Promise<{ release: () => Promise<void> }> } }).wakeLock;
        if (!wakeLock || document.visibilityState !== 'visible') return;
        const acquired = await wakeLock.request('screen');
        if (cancelled) void acquired.release();
        else lock = acquired;
      } catch {
        /* indisponível ou negado */
      }
    };
    void request();
    document.addEventListener('visibilitychange', request);
    return () => {
      cancelled = true;
      document.removeEventListener('visibilitychange', request);
      void lock?.release().catch(() => undefined);
    };
  }, []);
}

function CookTimer({ timer, detail }: { timer: RecipeStepTimer; detail: RecipeDetail }) {
  const timers = useTimers();
  const current = timers.findBySource(timer.id);
  const base = `${timer.label}${timer.temperature_c ? ` · ${timer.temperature_c} °C` : ''}`;
  if (!current) {
    return (
      <button
        type="button"
        className="cooktimer"
        onClick={() =>
          timers.start({
            label: timer.label, durationMs: timer.duration_seconds * 1000, recipeId: detail.recipe.id, recipeTitle: detail.recipe.title,
            recipeSlug: detail.recipe.slug, stepId: timer.step_id, sourceTimerId: timer.id, isMinimum: timer.is_minimum,
          })
        }
      >
        <Timer /> Iniciar: {base}
        <span className="clock">{timer.is_minimum ? 'mín. ' : ''}{formatDuration(timer.duration_seconds)}</span>
      </button>
    );
  }
  if (current.status === 'done') {
    return (
      <button type="button" className="cooktimer" onClick={() => timers.restart(current.id)}>
        <Check /> Tempo concluído: {base}
        <span className="clock" style={{ fontSize: 15 }}><RotateCcw size={15} style={{ verticalAlign: -2 }} /> repetir</span>
      </button>
    );
  }
  const running = current.status === 'running';
  return (
    <button type="button" className="cooktimer running" onClick={() => (running ? timers.pause(current.id) : timers.resume(current.id))} aria-label={running ? 'Pausar temporizador' : 'Retomar temporizador'}>
      {running ? <Pause /> : <Play />} {base}
      <span className="clock">{formatClock(remainingMs(current, timers.now))}</span>
    </button>
  );
}

function Cook() {
  const { slug } = useParams<{ slug: string }>();
  const router = useRouter();
  const params = useSearchParams();
  const { user, access, store, ready } = useSession();
  const { fail } = useToast();
  const timers = useTimers();
  useWakeLock();

  const { rows: recipes, loading: loadingRecipe } = useTable('recipes', { eq: { slug } });
  const recipe = recipes?.[0] ?? null;
  const { detail, loading: loadingDetail } = useRecipeDetail(recipe);
  const { rows: sessions } = useTable('cooking_sessions', user && recipe && access.has_access ? { eq: { recipe_id: recipe.id, status: 'active' }, order: [['created_at', 'desc']], limit: 1 } : null);

  const steps = useMemo(() => (detail ? flattenSteps(detail) : []), [detail]);
  const [session, setSession] = useState<CookingSession | null>(null);
  const [index, setIndex] = useState(0);
  const [finished, setFinished] = useState(false);
  const [big, setBig] = useState(false);
  const starting = useRef(false);
  const requested = params.get('f');

  useEffect(() => setBig(safeStorage.get('ccp.cook.big') === '1'), []);

  // retoma a sessão em andamento ou cria uma nova
  useEffect(() => {
    if (!recipe || !steps.length || sessions === undefined || session || starting.current) return;
    starting.current = true;
    const wanted = requested ? clampFactor(Number(requested)) : null;
    (async () => {
      try {
        const existing = sessions[0];
        if (existing) {
          const factor = wanted ?? existing.factor;
          if (factor !== existing.factor) await store.update('cooking_sessions', { id: existing.id }, { factor });
          setSession({ ...existing, factor });
          setIndex(Math.min(Math.max(0, existing.current_step), steps.length - 1));
        } else {
          const [created] = await store.insert('cooking_sessions', { recipe_id: recipe.id, factor: wanted ?? 1 });
          setSession(created);
          void invalidate('cooking_sessions');
        }
      } catch (error) {
        fail(error);
      }
    })();
  }, [recipe, steps.length, sessions, session, requested, store, fail]);

  const go = useCallback(
    (next: number) => {
      const target = Math.min(Math.max(0, next), steps.length - 1);
      setIndex(target);
      window.scrollTo({ top: 0 });
      if (session) {
        const done = Array.from({ length: target }, (_, i) => i);
        void store.update('cooking_sessions', { id: session.id }, { current_step: target, completed_steps: done }).catch(() => undefined);
      }
    },
    [session, steps.length, store],
  );

  async function finish() {
    setFinished(true);
    if (session) {
      try {
        await finishCookingSession(store, session.id, steps.map((_, i) => i));
      } catch (error) {
        fail(error);
      }
    }
  }

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (finished) return;
      if (event.key === 'ArrowRight' && index < steps.length - 1) go(index + 1);
      if (event.key === 'ArrowLeft' && index > 0) go(index - 1);
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [go, index, steps.length, finished]);

  const exit = () => router.push(recipe ? `/receitas/${recipe.slug}` : '/colecoes');
  const frame = (content: React.ReactNode) => (
    <div className="cook">
      <header className="cookhead">
        <button type="button" className="iconbtn" onClick={exit} aria-label="Sair do modo cozinheiro"><X /></button>
        <div className="title"><small>Modo cozinheiro</small><b>{recipe?.title ?? 'Receita'}</b></div>
      </header>
      <div className="cookbody">{content}</div>
    </div>
  );

  if (!ready || loadingRecipe || (access.has_access && loadingDetail)) return frame(<div className="skeleton" style={{ height: 240, opacity: 0.25 }} />);
  if (!recipe || !detail) return frame(<div className="cookdone"><h2>Receita não encontrada</h2><Link href="/colecoes" className="btn primary">Ver coleções</Link></div>);
  if (!access.has_access) return frame(<Paywall title="O modo cozinheiro faz parte do acesso da temporada" />);
  if (!steps.length) return frame(<div className="cookdone"><h2>Ficha em preparação</h2><p>O passo a passo desta receita ainda não foi estruturado.</p><button type="button" className="btn primary" onClick={exit}>Voltar à receita</button></div>);

  const factor = session?.factor ?? (requested ? clampFactor(Number(requested)) : 1);
  const current = steps[index];
  const others = timers.timers.filter((t) => t.status !== 'paused' && t.recipeId === recipe.id && !current.step.timers.some((st) => st.id === t.sourceTimerId));

  if (finished) {
    return frame(
      <div className="cookdone">
        <div className="seal"><Trophy /></div>
        <div className="eyebrow" style={{ color: '#e2c987' }}>✦ Receita concluída</div>
        <h2>{recipe.title}</h2>
        <p>Parabéns! A receita foi registrada no seu histórico e conta para os desafios da temporada.</p>
        <div className="row" style={{ justifyContent: 'center', marginTop: 8 }}>
          <Link href="/desafios" className="btn primary">Ver meus desafios</Link>
          <button type="button" className="btn light" onClick={exit}>Voltar à receita</button>
        </div>
      </div>,
    );
  }

  return (
    <div className={`cook ${big ? 'big' : ''}`}>
      <header className="cookhead">
        <button type="button" className="iconbtn" onClick={exit} aria-label="Sair do modo cozinheiro"><X /></button>
        <div className="title">
          <small>Etapa {index + 1} de {steps.length}{Math.abs(factor - 1) > 1e-9 ? ` · ${describeYield(recipe, factor)}` : ''}</small>
          <b>{recipe.title}</b>
        </div>
        <button
          type="button"
          className={`iconbtn ${big ? 'on' : ''}`}
          onClick={() => {
            safeStorage.set('ccp.cook.big', big ? '0' : '1');
            setBig(!big);
          }}
          aria-pressed={big}
          aria-label="Texto ampliado"
        >
          <ALargeSmall />
        </button>
      </header>
      <div className="cookprogress" role="progressbar" aria-valuemin={0} aria-valuemax={steps.length} aria-valuenow={index + 1} aria-label="Progresso da receita">
        <span style={{ width: `${((index + 1) / steps.length) * 100}%` }} />
      </div>

      <div className="cookbody">
        <div className="cookstep" key={current.step.id}>
          <div className="where">{current.part.component.title} · passo {current.stepInPart + 1} de {current.part.steps.length}</div>
          <p className="text">{current.step.instruction}</p>
          {current.step.tip && <p className="cookcard" style={{ marginTop: 16 }}>{current.step.tip}</p>}
        </div>

        {current.step.timers.map((timer) => <CookTimer key={timer.id} timer={timer} detail={detail} />)}

        {current.step.uses.length > 0 && (
          <div className="cookcard">
            <h4>Nesta etapa</h4>
            <ul>
              {current.step.uses.map((use) => {
                if (use.type === 'component') {
                  return <li key={use.component.id}><b>✦</b><span>{use.component.title} <span className="hint">(já preparado)</span></span></li>;
                }
                const scaled = scaleIngredient(use.ingredient, factor);
                return (
                  <li key={use.ingredient.id}>
                    <b>{scaled.text}</b>
                    <span>
                      {use.ingredient.display_name}{use.ingredient.preparation ? `, ${use.ingredient.preparation}` : ''}
                      {scaled.status === 'needs_validation' && <span className="hint"> (validar na prática)</span>}
                    </span>
                  </li>
                );
              })}
            </ul>
          </div>
        )}

        {others.length > 0 && (
          <div className="cookcard">
            <h4>Tempos em andamento</h4>
            <ul>
              {others.map((t) => (
                <li key={t.id}><b>{t.status === 'done' ? 'Concluído' : formatClock(remainingMs(t, timers.now))}</b><span>{t.label}</span></li>
              ))}
            </ul>
          </div>
        )}
      </div>

      <div className="cookfoot">
        <button type="button" className="btn back" onClick={() => go(index - 1)} disabled={index === 0} aria-label="Etapa anterior"><ArrowLeft /></button>
        {index < steps.length - 1 ? (
          <button type="button" className="btn primary" onClick={() => go(index + 1)}>Próxima etapa <ArrowRight /></button>
        ) : (
          <button type="button" className="btn primary" onClick={finish}><Check /> Concluir receita</button>
        )}
      </div>
    </div>
  );
}

export default function CookPage() {
  return (
    <Suspense>
      <Cook />
    </Suspense>
  );
}
