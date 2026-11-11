'use client';

import Link from 'next/link';
import { useState, type FormEvent } from 'react';
import { BellRing, Pause, Play, Plus, RotateCcw, Timer, Trash2 } from 'lucide-react';
import { useTimers } from '@/components/timers';
import { Empty, PageHead, usePageTitle } from '@/components/ui';
import { formatClock, formatDuration } from '@/lib/format';
import { progress, remainingMs, TIMER_PRESETS_MINUTES, type KitchenTimer } from '@/lib/timers';

function Ring({ timer, now }: { timer: KitchenTimer | null; now: number }) {
  const radius = 100;
  const circumference = 2 * Math.PI * radius;
  const value = timer ? progress(timer, now) : 0;
  return (
    <div className="ring" role="timer" aria-live="off">
      <svg viewBox="0 0 220 220" aria-hidden>
        <circle className="track" cx="110" cy="110" r={radius} />
        <circle className="bar" cx="110" cy="110" r={radius} strokeDasharray={circumference} strokeDashoffset={circumference * (1 - value)} />
      </svg>
      <div>
        <div className="time">{timer ? formatClock(remainingMs(timer, now)) : '00:00'}</div>
        {timer && <div className="muted small" style={{ marginTop: 6, maxWidth: 150 }}>{timer.status === 'done' ? 'Tempo concluído' : timer.label}</div>}
      </div>
    </div>
  );
}

export default function TimersPage() {
  usePageTitle('Temporizadores');
  const { timers, now, start, pause, resume, restart, extend, remove } = useTimers();
  const [label, setLabel] = useState('');
  const [minutes, setMinutes] = useState('10');
  const ordered = [...timers].sort((a, b) => {
    const rank = (t: KitchenTimer) => (t.status === 'done' ? 0 : t.status === 'running' ? 1 : 2);
    return rank(a) - rank(b) || remainingMs(a, now) - remainingMs(b, now);
  });
  const focus = ordered.find((t) => t.status !== 'paused') ?? ordered[0] ?? null;

  function create(event: FormEvent) {
    event.preventDefault();
    const value = Number(minutes.replace(',', '.'));
    if (!Number.isFinite(value) || value <= 0 || value > 24 * 60) return;
    start({ label: label.trim() || `Temporizador de ${formatDuration(value * 60)}`, durationMs: Math.round(value * 60_000) });
    setLabel('');
  }

  return (
    <>
      <PageHead eyebrow="No ritmo da receita" title="Temporizadores." sub="Acompanhe vários tempos ao mesmo tempo. Eles continuam contando mesmo se você trocar de tela ou fechar o app." />
      <div className="twocol">
        <section className="panel timerbox" style={{ maxWidth: 'none' }}>
          <div className="eyebrow">{focus?.recipeTitle ?? 'Temporizador independente'}</div>
          <Ring timer={focus} now={now} />
          {focus ? (
            <div className="row" style={{ justifyContent: 'center' }}>
              {focus.status === 'running' && <button type="button" className="btn dark" onClick={() => pause(focus.id)}><Pause /> Pausar</button>}
              {focus.status === 'paused' && <button type="button" className="btn dark" onClick={() => resume(focus.id)}><Play /> Retomar</button>}
              {focus.status === 'done' && <button type="button" className="btn primary" onClick={() => remove(focus.id)}><BellRing /> Ok, entendi</button>}
              <button type="button" className="btn outline" onClick={() => restart(focus.id)}><RotateCcw /> Reiniciar</button>
            </div>
          ) : (
            <p className="sub">Escolha um tempo para começar.</p>
          )}
          <div className="chips" style={{ justifyContent: 'center', marginTop: 20 }}>
            {TIMER_PRESETS_MINUTES.map((preset) => (
              <button key={preset} type="button" className="filter" onClick={() => start({ label: `Temporizador de ${preset} min`, durationMs: preset * 60_000 })}>{preset} min</button>
            ))}
          </div>
          <form className="row" style={{ marginTop: 18, justifyContent: 'center' }} onSubmit={create}>
            <input className="field" style={{ flex: '1 1 150px' }} placeholder="Nome (opcional)" aria-label="Nome do temporizador" value={label} onChange={(e) => setLabel(e.target.value)} maxLength={60} />
            <input className="field" style={{ width: 92 }} inputMode="decimal" aria-label="Minutos" value={minutes} onChange={(e) => setMinutes(e.target.value)} />
            <button type="submit" className="btn dark"><Plus /> Criar</button>
          </form>
        </section>

        <section className="panel">
          <div className="panelhead">
            <div><div className="eyebrow">Em andamento</div><h2 style={{ marginTop: 6 }}>Seus temporizadores</h2></div>
            <span className="pill">{timers.length}</span>
          </div>
          {ordered.length ? (
            <div className="stack">
              {ordered.map((timer) => (
                <div key={timer.id} className={`timerrow ${timer.status === 'done' ? 'done' : ''}`}>
                  <div className="clock">{formatClock(remainingMs(timer, now))}</div>
                  <div className="grow">
                    <b>{timer.label}</b>
                    <div className="muted small">
                      {timer.recipeSlug ? <Link href={`/receitas/${timer.recipeSlug}`}>{timer.recipeTitle}</Link> : 'Temporizador manual'}
                      {' · '}{timer.isMinimum ? 'mínimo de ' : ''}{formatDuration(timer.durationMs / 1000)}
                      {timer.status === 'paused' ? ' · pausado' : timer.status === 'done' ? ' · concluído' : ''}
                    </div>
                  </div>
                  {timer.status === 'running' && <button type="button" className="iconbtn" onClick={() => pause(timer.id)} aria-label={`Pausar ${timer.label}`}><Pause /></button>}
                  {timer.status === 'paused' && <button type="button" className="iconbtn" onClick={() => resume(timer.id)} aria-label={`Retomar ${timer.label}`}><Play /></button>}
                  {timer.status === 'done' && <button type="button" className="iconbtn" onClick={() => restart(timer.id)} aria-label={`Repetir ${timer.label}`}><RotateCcw /></button>}
                  {timer.status !== 'done' && <button type="button" className="btn outline sm" onClick={() => extend(timer.id, 60_000)} aria-label={`Adicionar 1 minuto a ${timer.label}`}>+1 min</button>}
                  <button type="button" className="iconbtn plain" onClick={() => remove(timer.id)} aria-label={`Excluir ${timer.label}`}><Trash2 /></button>
                </div>
              ))}
            </div>
          ) : (
            <Empty icon={Timer} title="Nenhum temporizador ativo">
              Use os atalhos ao lado ou inicie os tempos direto nas etapas de uma receita.
            </Empty>
          )}
        </section>
      </div>
    </>
  );
}
