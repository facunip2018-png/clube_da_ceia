'use client';

import Link from 'next/link';
import { useMemo, useState, type FormEvent } from 'react';
import { CalendarHeart, Check, Pencil, Plus, ShoppingBasket, Trash2, UtensilsCrossed } from 'lucide-react';
import { invalidate, useCatalog, useIngredientCatalog, useRecipeDetails, useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { addRecipeToPlan, addRecipeToShoppingList, createPlan, removeRecipeFromShoppingList } from '@/data/actions';
import { Guard } from '@/components/gates';
import { PlanForm, type PlanFormValue } from '@/components/plan-form';
import { useToast } from '@/components/toast';
import { useDialog } from '@/components/dialogs';
import { Cover, Empty, Loading, Notice, PageHead, Progress, Sheet, Stepper, usePageTitle } from '@/components/ui';
import { buildSchedule, daysUntil } from '@/lib/schedule';
import { describeYield, factorFromTarget, suggestFactorForGuests, targetFromFactor, yieldControl } from '@/lib/scaling';
import { formatDate, formatQuantity, normalizeText } from '@/lib/format';
import type { MealPlan, PlanRecipe, Recipe } from '@/lib/types';

const OCCASION: Record<MealPlan['occasion'], string> = { natal: 'Natal', ano_novo: 'Ano-Novo', outro: 'Celebração' };
const BLOCKS = [0, 15, 30, 45, 60];

function RecipePicker({ plan, chosen, onClose }: { plan: MealPlan; chosen: PlanRecipe[]; onClose: () => void }) {
  const { store } = useSession();
  const { fail } = useToast();
  const { recipes, collections } = useCatalog();
  const [q, setQ] = useState('');
  const available = useMemo(
    () => recipes.filter((r) => r.status === 'published' && r.kind !== 'component' && (!q || normalizeText(r.title).includes(normalizeText(q)))),
    [recipes, q],
  );

  async function toggle(recipe: Recipe) {
    try {
      const current = chosen.find((c) => c.recipe_id === recipe.id);
      if (current) {
        await store.remove('plan_recipes', { id: current.id });
        await invalidate('plan_recipes', 'refresh_my_challenges');
      } else {
        await addRecipeToPlan(store, plan.id, recipe.id, suggestFactorForGuests(recipe, plan.guests).factor);
      }
    } catch (error) {
      fail(error);
    }
  }

  return (
    <Sheet title="Escolha as receitas" eyebrow={plan.title} onClose={onClose} wide>
      <input className="field" type="search" placeholder="Filtrar receitas…" aria-label="Filtrar receitas" value={q} onChange={(e) => setQ(e.target.value)} />
      <div className="tasklist" style={{ marginTop: 14 }}>
        {available.map((recipe) => {
          const on = chosen.some((c) => c.recipe_id === recipe.id);
          return (
            <label key={recipe.id} className="task" style={{ cursor: 'pointer' }}>
              <input type="checkbox" className="check" checked={on} onChange={() => toggle(recipe)} />
              <span className="grow">
                <span className="t"><b>{recipe.title}</b></span>
                <small>{collections.find((c) => c.id === recipe.collection_id)?.name}{recipe.yield_text ? ` · rende ${recipe.yield_text}` : ''}</small>
              </span>
            </label>
          );
        })}
        {!available.length && (
          <Empty icon={UtensilsCrossed} title="Nenhuma receita disponível">
            {q ? 'Nenhuma receita publicada corresponde ao filtro.' : 'As receitas aparecem aqui assim que forem publicadas pela curadoria.'}
          </Empty>
        )}
      </div>
      <button type="button" className="btn dark block" style={{ marginTop: 16 }} onClick={onClose}>Concluir</button>
    </Sheet>
  );
}

function PlanView({ plan, plans, onSelect, onNew }: { plan: MealPlan; plans: MealPlan[]; onSelect: (id: string) => void; onNew: () => void }) {
  const { store } = useSession();
  const { toast, fail } = useToast();
  const { confirm } = useDialog();
  const { recipes } = useCatalog();
  const catalog = useIngredientCatalog();
  const { rows: planRecipes } = useTable('plan_recipes', { eq: { plan_id: plan.id }, order: [['position', 'asc']] });
  const { rows: tasks } = useTable('plan_tasks', { eq: { plan_id: plan.id }, order: [['position', 'asc']] });
  const [picking, setPicking] = useState(false);
  const [editing, setEditing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [newTask, setNewTask] = useState('');

  const menu = useMemo(
    () => (planRecipes ?? []).map((item) => ({ item, recipe: recipes.find((r) => r.id === item.recipe_id) })).filter((m): m is { item: PlanRecipe; recipe: Recipe } => Boolean(m.recipe)),
    [planRecipes, recipes],
  );
  const menuRecipes = useMemo(() => menu.map((m) => m.recipe), [menu]);
  const { details } = useRecipeDetails(menuRecipes);
  const schedule = useMemo(() => {
    if (!plan.event_date) return null;
    return buildSchedule({
      eventDate: plan.event_date,
      serveTime: plan.serve_time,
      blockMinutes: plan.default_block_minutes,
      recipes: details.map((detail) => ({ detail, factor: menu.find((m) => m.recipe.id === detail.recipe.id)?.item.factor ?? 1 })),
    });
  }, [plan, details, menu]);

  const done = (tasks ?? []).filter((t) => t.is_done).length;
  const total = tasks?.length ?? 0;
  const days = plan.event_date ? daysUntil(plan.event_date) : null;

  const run = async (fn: () => Promise<unknown>, ...tables: Parameters<typeof invalidate>) => {
    try {
      await fn();
      await invalidate(...tables);
    } catch (error) {
      fail(error);
    }
  };

  async function generateList() {
    setBusy(true);
    try {
      let count = 0;
      for (const detail of details.filter((d) => d.hasContent)) {
        const factor = menu.find((m) => m.recipe.id === detail.recipe.id)?.item.factor ?? 1;
        count += await addRecipeToShoppingList(store, detail, factor, catalog);
      }
      toast(count ? 'Lista de compras atualizada com o cardápio' : 'Nenhuma receita do cardápio tem ficha com ingredientes', {
        action: count ? { label: 'Ver lista', onClick: () => window.location.assign('/lista') } : undefined,
      });
    } catch (error) {
      fail(error);
    } finally {
      setBusy(false);
    }
  }

  async function addTask(event: FormEvent) {
    event.preventDefault();
    const title = newTask.trim();
    if (!title) return;
    setNewTask('');
    await run(() => store.insert('plan_tasks', { plan_id: plan.id, title, kind: 'custom', position: total + 1 }), 'plan_tasks', 'refresh_my_challenges');
  }

  async function removePlan() {
    if (!(await confirm({ title: 'Excluir planejamento?', message: `“${plan.title}” será apagado com o cardápio e o checklist. A lista de compras é mantida.`, confirmLabel: 'Excluir', danger: true }))) return;
    await run(() => store.remove('meal_plans', { id: plan.id }), 'meal_plans', 'plan_recipes', 'plan_tasks', 'refresh_my_challenges');
    toast('Planejamento excluído');
  }

  return (
    <>
      <div className="eventbox" style={{ marginBottom: 18, flexWrap: 'wrap' }}>
        <div className="datebox">
          <b>{plan.event_date ? formatDate(plan.event_date, { day: '2-digit' }) : '–'}</b>
          <small>{plan.event_date ? formatDate(plan.event_date, { month: 'short' }).replace('.', '') : 'data'}</small>
        </div>
        <div className="grow">
          <h2 style={{ fontSize: 22 }}>{plan.title}</h2>
          <div className="muted small">
            {OCCASION[plan.occasion]} · {plan.guests} {plan.guests === 1 ? 'convidado' : 'convidados'}
            {plan.serve_time ? ` · servir às ${plan.serve_time.slice(0, 5)}` : ''}
            {days != null && (days > 0 ? ` · faltam ${days} ${days === 1 ? 'dia' : 'dias'}` : days === 0 ? ' · é hoje!' : ' · evento realizado')}
          </div>
        </div>
        <div className="row">
          {plans.length > 1 && (
            <select className="select" style={{ width: 'auto' }} value={plan.id} onChange={(e) => onSelect(e.target.value)} aria-label="Trocar de planejamento">
              {plans.map((p) => <option key={p.id} value={p.id}>{p.title}</option>)}
            </select>
          )}
          <button type="button" className="btn outline sm" onClick={() => setEditing(true)}><Pencil /> Editar</button>
          <button type="button" className="btn outline sm" onClick={onNew}><Plus /> Novo</button>
          <button type="button" className="iconbtn" onClick={removePlan} aria-label="Excluir planejamento"><Trash2 /></button>
        </div>
      </div>

      <div className="twocol">
        <section className="panel">
          <div className="panelhead">
            <div><div className="eyebrow">Cardápio</div><h2 style={{ marginTop: 6 }}>Receitas da ceia</h2></div>
            <button type="button" className="btn dark sm" onClick={() => setPicking(true)}><Plus /> Adicionar receitas</button>
          </div>
          {menu.length ? (
            <div className="stack">
              {menu.map(({ item, recipe }) => {
                const control = yieldControl(recipe);
                const suggestion = suggestFactorForGuests(recipe, plan.guests);
                return (
                  <div key={item.id}>
                    <div className="menuitem">
                      <div className="thumb" style={{ position: 'relative' }}><Cover src={recipe.cover_image} alt="" sizes="64px" /></div>
                      <div style={{ minWidth: 0 }}>
                        <h3><Link href={`/receitas/${recipe.slug}`}>{recipe.title}</Link></h3>
                        <span className="muted small">{describeYield(recipe, item.factor) ?? 'rendimento não informado'}</span>
                      </div>
                      <button type="button" className="iconbtn plain" aria-label={`Remover ${recipe.title} do cardápio`}
                        onClick={() => run(async () => { await store.remove('plan_recipes', { id: item.id }); await removeRecipeFromShoppingList(store, recipe.id); }, 'plan_recipes', 'refresh_my_challenges')}>
                        <Trash2 />
                      </button>
                    </div>
                    <div className="row" style={{ margin: '8px 2px 0', justifyContent: 'space-between' }}>
                      <Stepper
                        label={`Quantidade de ${recipe.title}`}
                        value={targetFromFactor(control, item.factor)}
                        min={control.min}
                        max={control.max}
                        step={control.step}
                        onChange={(target) => run(() => store.update('plan_recipes', { id: item.id }, { factor: factorFromTarget(control, target) }), 'plan_recipes')}
                        format={(value) => formatQuantity(value, control.unit)}
                      />
                      {suggestion.basedOnServings ? (
                        suggestion.factor !== item.factor && (
                          <button type="button" className="textbtn" onClick={() => run(() => store.update('plan_recipes', { id: item.id }, { factor: suggestion.factor }), 'plan_recipes')}>
                            Sugestão: {suggestion.message}
                          </button>
                        )
                      ) : (
                        <span className="muted small" style={{ flex: 1, minWidth: 180 }}>Porções não informadas no material — ajuste a quantidade manualmente.</span>
                      )}
                    </div>
                  </div>
                );
              })}
              <hr className="divider" />
              <button type="button" className="btn primary" onClick={generateList} disabled={busy}><ShoppingBasket /> Gerar lista de compras do cardápio</button>
            </div>
          ) : (
            <Empty icon={UtensilsCrossed} title="Cardápio vazio" action={<button type="button" className="btn dark" onClick={() => setPicking(true)}>Escolher receitas</button>}>
              Adicione receitas de qualquer coleção para montar o cardápio, o cronograma e a lista de compras.
            </Empty>
          )}
        </section>

        <section className="panel">
          <div className="panelhead">
            <div><div className="eyebrow">Seu roteiro</div><h2 style={{ marginTop: 6 }}>Preparativos da ceia</h2></div>
            <span className="pill">{done}/{total}</span>
          </div>
          <Progress value={total ? done / total : 0} label="Checklist de preparação" />
          <div className="tasklist" style={{ marginTop: 14 }}>
            {(tasks ?? []).map((task) => (
              <div key={task.id} className={`task ${task.is_done ? 'done' : ''}`}>
                <input
                  type="checkbox"
                  className="check"
                  checked={task.is_done}
                  aria-label={task.title}
                  onChange={() => run(() => store.update('plan_tasks', { id: task.id }, { is_done: !task.is_done, done_at: task.is_done ? null : new Date().toISOString() }), 'plan_tasks', 'refresh_my_challenges')}
                />
                <span className="grow">
                  <span className="t">{task.title}</span>
                  {task.due_at && <small>até {formatDate(task.due_at, { day: '2-digit', month: 'short' })}</small>}
                </span>
                {task.kind === 'custom' && (
                  <button type="button" className="iconbtn plain" aria-label={`Excluir tarefa ${task.title}`} onClick={() => run(() => store.remove('plan_tasks', { id: task.id }), 'plan_tasks', 'refresh_my_challenges')}><Trash2 /></button>
                )}
              </div>
            ))}
          </div>
          <form className="row" style={{ marginTop: 12 }} onSubmit={addTask}>
            <input className="field grow" placeholder="Nova tarefa (ex.: buscar a toalha de mesa)" aria-label="Nova tarefa" value={newTask} onChange={(e) => setNewTask(e.target.value)} maxLength={120} />
            <button type="submit" className="btn outline" disabled={!newTask.trim()}><Plus /> Adicionar</button>
          </form>
        </section>
      </div>

      <section className="panel" style={{ marginTop: 18 }}>
        <div className="panelhead">
          <div><div className="eyebrow">Cronograma de preparo</div><h2 style={{ marginTop: 6 }}>Quando começar cada receita</h2></div>
          <div className="row">
            <label className="label" htmlFor="block">Bloco de organização</label>
            <select id="block" className="select" style={{ width: 'auto' }} value={plan.default_block_minutes}
              onChange={(e) => run(() => store.update('meal_plans', { id: plan.id }, { default_block_minutes: Number(e.target.value) }), 'meal_plans')}>
              {BLOCKS.map((b) => <option key={b} value={b}>{b === 0 ? 'Só tempos da ficha' : `${b} min por parte`}</option>)}
            </select>
          </div>
        </div>
        {!schedule ? (
          <Notice>Defina a data da ceia para montar o cronograma.</Notice>
        ) : !menu.length ? (
          <p className="sub">O cronograma aparece quando houver receitas no cardápio.</p>
        ) : (
          <>
            <ol className="timeline">
              {schedule.entries.map((entry) => (
                <li key={entry.key} className={entry.kind}>
                  <div className="when"><b>{entry.at.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}</b>{entry.at.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })}</div>
                  <div className="dot" />
                  <div className="what"><b>{entry.title}</b>{entry.detail && <small>{entry.detail}</small>}</div>
                </li>
              ))}
            </ol>
            {schedule.withoutTimes.length > 0 && (
              <Notice>Sem ficha disponível para calcular horários: {schedule.withoutTimes.join(', ')}.</Notice>
            )}
            <p className="muted small" style={{ marginTop: 12 }}>
              O cronograma é calculado de trás para frente a partir do horário de servir{plan.serve_time ? '' : ' (20:00, por padrão)'}, usando apenas os tempos que constam nas fichas.
              O “bloco de organização” é uma folga sua para cada parte da receita — não é um tempo informado pelo material.
            </p>
          </>
        )}
      </section>

      {picking && <RecipePicker plan={plan} chosen={planRecipes ?? []} onClose={() => setPicking(false)} />}
      {editing && (
        <Sheet title="Editar planejamento" onClose={() => setEditing(false)}>
          <PlanForm
            initial={{ title: plan.title, occasion: plan.occasion, event_date: plan.event_date ?? undefined, serve_time: plan.serve_time, guests: plan.guests }}
            submitLabel="Salvar"
            onSubmit={async (value: PlanFormValue) => {
              await run(() => store.update('meal_plans', { id: plan.id }, value), 'meal_plans', 'refresh_my_challenges');
              setEditing(false);
              toast('Planejamento atualizado');
            }}
          />
        </Sheet>
      )}
    </>
  );
}

function Planner() {
  const { store } = useSession();
  const { toast, fail } = useToast();
  const { rows: plans, loading } = useTable('meal_plans', { order: [['created_at', 'desc']] });
  const [selected, setSelected] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [busy, setBusy] = useState(false);
  const active = useMemo(() => (plans ?? []).filter((p) => p.status !== 'archived'), [plans]);
  const plan = active.find((p) => p.id === selected) ?? active[0];

  if (loading) return <Loading />;

  if (!plan || creating) {
    return (
      <div className="twocol">
        <section className="panel">
          <div className="eyebrow">Novo planejamento</div>
          <h2 style={{ margin: '6px 0 18px' }}>Conte sobre sua ceia</h2>
          <PlanForm
            submitLabel="Criar meu planejamento"
            busy={busy}
            onSubmit={async (value) => {
              setBusy(true);
              try {
                const created = await createPlan(store, value);
                setSelected(created.id);
                setCreating(false);
                toast('Planejamento criado. Agora escolha as receitas!');
              } catch (error) {
                fail(error);
              } finally {
                setBusy(false);
              }
            }}
          />
          {creating && <button type="button" className="textbtn" style={{ marginTop: 10 }} onClick={() => setCreating(false)}>← Voltar ao planejamento atual</button>}
        </section>
        <section className="panel">
          <div className="eyebrow">Seu roteiro</div>
          <h2 style={{ margin: '6px 0 14px' }}>O que você recebe</h2>
          <ul className="checklist">
            <li className="ok"><span className="mark"><Check /></span><div><b>Cardápio com quantidades</b><small>Ajuste cada receita pelo rendimento original.</small></div></li>
            <li className="ok"><span className="mark"><Check /></span><div><b>Cronograma de preparo</b><small>Calculado a partir do horário de servir, com os tempos das fichas.</small></div></li>
            <li className="ok"><span className="mark"><Check /></span><div><b>Checklist de organização</b><small>Tarefas com datas sugeridas até o dia da ceia.</small></div></li>
            <li className="ok"><span className="mark"><Check /></span><div><b>Lista de compras</b><small>Ingredientes do cardápio somados por categoria.</small></div></li>
          </ul>
        </section>
      </div>
    );
  }

  return <PlanView key={plan.id} plan={plan} plans={active} onSelect={setSelected} onNew={() => setCreating(true)} />;
}

export default function PlannerPage() {
  usePageTitle('Minha ceia');
  return (
    <>
      <PageHead eyebrow="Organize com tranquilidade" title="Minha ceia, do meu jeito." sub="Monte o cardápio com receitas de diferentes coleções e receba cronograma, checklist e lista de compras.">
        <span className="pill"><CalendarHeart /> PLANEJADOR</span>
      </PageHead>
      <Guard access what="O planejamento da ceia">
        <Planner />
      </Guard>
    </>
  );
}
