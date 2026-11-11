'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { BellRing, Timer } from 'lucide-react';
import { addTime, createTimer, pauseTimer, remainingMs, restartTimer, resumeTimer, sanitizeTimers, tick, type KitchenTimer, type NewTimer } from '@/lib/timers';
import { formatClock } from '@/lib/format';
import { newId, readJson, writeJson } from '@/lib/safe-storage';
import { useToast } from './toast';

const STORAGE_KEY = 'ccp.timers.v1';

interface TimerApi {
  timers: KitchenTimer[];
  now: number;
  start: (input: NewTimer) => KitchenTimer;
  pause: (id: string) => void;
  resume: (id: string) => void;
  restart: (id: string) => void;
  extend: (id: string, ms: number) => void;
  remove: (id: string) => void;
  /** temporizador já iniciado a partir de um tempo da ficha */
  findBySource: (sourceTimerId: string) => KitchenTimer | undefined;
}

const TimerContext = createContext<TimerApi | null>(null);

export function TimerProvider({ children }: { children: ReactNode }) {
  const [timers, setTimers] = useState<KitchenTimer[]>([]);
  const [now, setNow] = useState(() => Date.now());
  const loaded = useRef(false);
  const audio = useRef<AudioContext | null>(null);
  const { toast } = useToast();

  // Os temporizadores ficam salvos com o horário de término: sobrevivem a troca de tela e recarga.
  useEffect(() => {
    setTimers(sanitizeTimers(readJson<unknown>(STORAGE_KEY, [])));
    loaded.current = true;
  }, []);
  useEffect(() => {
    if (loaded.current) writeJson(STORAGE_KEY, timers);
  }, [timers]);

  const unlockAudio = useCallback(() => {
    try {
      const Ctor = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
      if (!Ctor) return;
      audio.current ??= new Ctor();
      if (audio.current.state === 'suspended') void audio.current.resume();
    } catch {
      /* áudio indisponível */
    }
  }, []);

  const chime = useCallback(() => {
    const ctx = audio.current;
    if (!ctx || ctx.state !== 'running') return;
    [0, 0.28, 0.56].forEach((offset, index) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.value = [880, 1108, 1318][index];
      gain.gain.setValueAtTime(0.0001, ctx.currentTime + offset);
      gain.gain.exponentialRampToValueAtTime(0.25, ctx.currentTime + offset + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + offset + 0.6);
      osc.connect(gain).connect(ctx.destination);
      osc.start(ctx.currentTime + offset);
      osc.stop(ctx.currentTime + offset + 0.65);
    });
  }, []);

  const announce = useCallback(
    (finished: KitchenTimer[]) => {
      if (!finished.length) return;
      chime();
      try {
        navigator.vibrate?.([300, 120, 300]);
      } catch {
        /* sem vibração */
      }
      for (const timer of finished) {
        toast(`Tempo concluído: ${timer.label}`);
        try {
          if (typeof Notification !== 'undefined' && Notification.permission === 'granted' && document.visibilityState !== 'visible') {
            new Notification('Tempo concluído', { body: timer.recipeTitle ? `${timer.label} — ${timer.recipeTitle}` : timer.label, icon: '/icons/icon-192.png', tag: timer.id });
          }
        } catch {
          /* notificações indisponíveis */
        }
      }
    },
    [chime, toast],
  );

  const latest = useRef<KitchenTimer[]>([]);
  const announced = useRef(new Set<string>());
  useEffect(() => {
    latest.current = timers;
  }, [timers]);

  const running = timers.some((t) => t.status === 'running');
  useEffect(() => {
    const update = () => {
      const current = Date.now();
      setNow(current);
      const fresh = tick(latest.current, current).finished.filter((t) => !announced.current.has(`${t.id}:${t.finishedAt}`));
      if (!fresh.length) return;
      fresh.forEach((t) => announced.current.add(`${t.id}:${t.finishedAt}`));
      setTimers((list) => tick(list, current).timers);
      announce(fresh);
    };
    update();
    if (!running) return;
    const interval = window.setInterval(update, 500);
    document.addEventListener('visibilitychange', update);
    return () => {
      window.clearInterval(interval);
      document.removeEventListener('visibilitychange', update);
    };
  }, [running, announce]);

  const api = useMemo<TimerApi>(() => {
    const change = (id: string, fn: (t: KitchenTimer, at: number) => KitchenTimer) =>
      setTimers((list) => list.map((t) => (t.id === id ? fn(t, Date.now()) : t)));
    return {
      timers,
      now,
      start: (input) => {
        unlockAudio();
        try {
          if (typeof Notification !== 'undefined' && Notification.permission === 'default') void Notification.requestPermission();
        } catch {
          /* notificações indisponíveis */
        }
        const timer = createTimer(input, Date.now(), newId());
        setTimers((list) => [...list.filter((t) => !(input.sourceTimerId && t.sourceTimerId === input.sourceTimerId)), timer]);
        return timer;
      },
      pause: (id) => change(id, pauseTimer),
      resume: (id) => {
        unlockAudio();
        change(id, resumeTimer);
      },
      restart: (id) => {
        unlockAudio();
        change(id, restartTimer);
      },
      extend: (id, ms) => change(id, (t, at) => addTime(t, ms, at)),
      remove: (id) => setTimers((list) => list.filter((t) => t.id !== id)),
      findBySource: (sourceTimerId) => timers.find((t) => t.sourceTimerId === sourceTimerId),
    };
  }, [timers, now, unlockAudio]);

  return <TimerContext.Provider value={api}>{children}</TimerContext.Provider>;
}

export function useTimers(): TimerApi {
  const api = useContext(TimerContext);
  if (!api) throw new Error('useTimers precisa estar dentro de <TimerProvider>.');
  return api;
}

/** Atalho flutuante: mostra o temporizador mais próximo do fim em qualquer tela. */
export function TimerDock() {
  const { timers, now } = useTimers();
  const pathname = usePathname();
  if (pathname.startsWith('/temporizadores') || pathname.startsWith('/cozinhar')) return null;
  const done = timers.filter((t) => t.status === 'done');
  const active = timers.filter((t) => t.status === 'running').sort((a, b) => remainingMs(a, now) - remainingMs(b, now));
  if (!done.length && !active.length) return null;
  const first = done[0] ?? active[0];
  const others = done.length + active.length - 1;
  return (
    <Link href="/temporizadores" className={`timerdock noprint ${done.length ? 'done' : ''}`} aria-label="Abrir temporizadores">
      <span className="ico">{done.length ? <BellRing /> : <Timer />}</span>
      <span>
        {done.length ? 'Tempo concluído' : <b>{formatClock(remainingMs(first, now))}</b>}
        {others > 0 && <span style={{ opacity: 0.75, fontWeight: 500 }}> +{others}</span>}
      </span>
    </Link>
  );
}
