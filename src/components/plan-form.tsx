'use client';

import { useState, type FormEvent } from 'react';
import type { MealPlan } from '@/lib/types';

export interface PlanFormValue {
  title: string;
  occasion: MealPlan['occasion'];
  event_date: string;
  serve_time: string | null;
  guests: number;
}

/** Ocasiões do MVP, com data e horário sugeridos para cada uma. */
const PRESETS = [
  { id: 'ceia-natal', label: 'Ceia de Natal', occasion: 'natal' as const, monthDay: '12-24', time: '20:00', title: 'Minha Ceia em Família' },
  { id: 'almoco-natal', label: 'Almoço de Natal', occasion: 'natal' as const, monthDay: '12-25', time: '13:00', title: 'Almoço de Natal' },
  { id: 'reveillon', label: 'Réveillon / Ano-Novo', occasion: 'ano_novo' as const, monthDay: '12-31', time: '22:00', title: 'Ceia de Ano-Novo' },
];

function presetDate(monthDay: string): string {
  const today = new Date();
  const candidate = `${today.getFullYear()}-${monthDay}`;
  const todayIso = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
  return candidate >= todayIso ? candidate : `${today.getFullYear() + 1}-${monthDay}`;
}

export function PlanForm({ initial, submitLabel, busy, onSubmit }: { initial?: Partial<PlanFormValue>; submitLabel: string; busy?: boolean; onSubmit: (value: PlanFormValue) => void }) {
  const [preset, setPreset] = useState(initial?.occasion === 'ano_novo' ? 'reveillon' : 'ceia-natal');
  const [title, setTitle] = useState(initial?.title ?? PRESETS[0].title);
  const [date, setDate] = useState(initial?.event_date ?? presetDate(PRESETS[0].monthDay));
  const [time, setTime] = useState(initial?.serve_time?.slice(0, 5) ?? PRESETS[0].time);
  const [guests, setGuests] = useState(String(initial?.guests ?? 10));
  const editing = Boolean(initial?.title);

  function choose(id: string) {
    const next = PRESETS.find((p) => p.id === id) ?? PRESETS[0];
    const previous = PRESETS.find((p) => p.id === preset);
    setPreset(id);
    if (!editing) {
      setDate(presetDate(next.monthDay));
      setTime(next.time);
      if (!title.trim() || title === previous?.title) setTitle(next.title);
    }
  }

  function submit(event: FormEvent) {
    event.preventDefault();
    const count = Math.min(200, Math.max(1, Math.round(Number(guests) || 1)));
    onSubmit({
      title: title.trim() || 'Minha ceia',
      occasion: PRESETS.find((p) => p.id === preset)?.occasion ?? 'natal',
      event_date: date,
      serve_time: time || null,
      guests: count,
    });
  }

  return (
    <form className="formgrid" onSubmit={submit}>
      <div className="group">
        <label htmlFor="plan-occasion">Ocasião</label>
        <select id="plan-occasion" className="select" value={preset} onChange={(e) => choose(e.target.value)}>
          {PRESETS.map((p) => <option key={p.id} value={p.id}>{p.label}</option>)}
        </select>
      </div>
      <div className="group">
        <label htmlFor="plan-date">Data</label>
        <input id="plan-date" className="field" type="date" value={date} onChange={(e) => setDate(e.target.value)} required />
      </div>
      <div className="group full">
        <label htmlFor="plan-title">Nome do evento</label>
        <input id="plan-title" className="field" value={title} onChange={(e) => setTitle(e.target.value)} maxLength={80} required />
      </div>
      <div className="group">
        <label htmlFor="plan-guests">Quantas pessoas?</label>
        <input id="plan-guests" className="field" type="number" inputMode="numeric" min={1} max={200} value={guests} onChange={(e) => setGuests(e.target.value)} required />
      </div>
      <div className="group">
        <label htmlFor="plan-time">Horário de servir</label>
        <input id="plan-time" className="field" type="time" value={time} onChange={(e) => setTime(e.target.value)} />
      </div>
      <div className="group full">
        <button type="submit" className="btn dark" disabled={busy || !date}>{submitLabel} →</button>
      </div>
    </form>
  );
}
