'use client';

import Link from 'next/link';
import { useState } from 'react';
import { CalendarHeart, Check } from 'lucide-react';
import type { Recipe } from '@/lib/types';
import { useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { addRecipeToPlan, createPlan } from '@/data/actions';
import { formatDate } from '@/lib/format';
import { Sheet } from './ui';
import { useToast } from './toast';
import { PlanForm, type PlanFormValue } from './plan-form';

/** Folha "Adicionar à minha ceia": escolhe um planejamento existente ou cria um novo. */
export function AddToPlanSheet({ recipe, factor, onClose }: { recipe: Recipe; factor: number; onClose: () => void }) {
  const { store } = useSession();
  const { toast, fail } = useToast();
  const { rows: plans, loading } = useTable('meal_plans', { eq: { status: 'active' }, order: [['event_date', 'asc']] });
  const [busy, setBusy] = useState(false);

  async function add(planId: string, title: string) {
    setBusy(true);
    try {
      const result = await addRecipeToPlan(store, planId, recipe.id, factor);
      toast(result === 'added' ? `Adicionada a “${title}”` : `Já está no cardápio de “${title}”`);
      onClose();
    } catch (error) {
      fail(error);
    } finally {
      setBusy(false);
    }
  }

  async function create(value: PlanFormValue) {
    setBusy(true);
    try {
      const plan = await createPlan(store, value);
      await addRecipeToPlan(store, plan.id, recipe.id, factor);
      toast(`Planejamento criado com “${recipe.title}”`);
      onClose();
    } catch (error) {
      fail(error);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Sheet title="Adicionar à minha ceia" eyebrow={recipe.title} onClose={onClose}>
      {loading ? (
        <div className="skeleton" style={{ height: 120 }} />
      ) : plans?.length ? (
        <div className="stack">
          {plans.map((plan) => (
            <button key={plan.id} type="button" className="task" style={{ textAlign: 'left', width: '100%' }} disabled={busy} onClick={() => add(plan.id, plan.title)}>
              <span className="stat-icon"><CalendarHeart /></span>
              <span className="grow">
                <b>{plan.title}</b>
                <small>{plan.event_date ? formatDate(plan.event_date) : 'Sem data'} · {plan.guests} convidados</small>
              </span>
              <Check size={18} color="var(--green)" />
            </button>
          ))}
          <Link href="/minha-ceia" className="textbtn" onClick={onClose}>Gerenciar planejamentos →</Link>
        </div>
      ) : (
        <>
          <p className="sub" style={{ marginBottom: 14 }}>Você ainda não tem um planejamento. Conte sobre a sua ceia para começar:</p>
          <PlanForm submitLabel="Criar e adicionar receita" busy={busy} onSubmit={create} />
        </>
      )}
    </Sheet>
  );
}
