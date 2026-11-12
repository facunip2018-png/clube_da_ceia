'use client';

import Link from 'next/link';
import { useParams } from 'next/navigation';
import { useEffect, useMemo, useState, type FormEvent } from 'react';
import { Check, CircleAlert, Eye, Info, RotateCcw, Save, TriangleAlert, X } from 'lucide-react';
import { useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { StatusPill } from '@/components/cards';
import { PERMISSION_LABELS, useAdminAction } from '@/components/admin';
import { useDialog } from '@/components/dialogs';
import { Empty, Loading, Notice } from '@/components/ui';
import { statusActions } from '@/lib/editorial';
import { formatDuration, pageRange } from '@/lib/format';
import { assembleRecipeDetail, ROLE_LABELS } from '@/lib/recipe-view';
import type { Recipe, RecipeIngredient, RecipeStep, ReviewFlag } from '@/lib/types';

const TABLES = ['recipes', 'review_flags', 'recipe_ingredients', 'recipe_steps', 'admin_audit_logs'] as const;
const numberOrNull = (value: string) => (value.trim() === '' ? null : Number(value.replace(',', '.')));

function IngredientRow({ ingredient }: { ingredient: RecipeIngredient }) {
  const { store } = useSession();
  const act = useAdminAction();
  const [quantity, setQuantity] = useState(ingredient.quantity != null ? String(ingredient.quantity) : '');
  const [unit, setUnit] = useState(ingredient.unit ?? '');
  const [name, setName] = useState(ingredient.display_name);
  const [text, setText] = useState(ingredient.quantity_text ?? '');
  const dirty = quantity !== (ingredient.quantity != null ? String(ingredient.quantity) : '') || unit !== (ingredient.unit ?? '') || name !== ingredient.display_name || text !== (ingredient.quantity_text ?? '');

  async function save() {
    const value = numberOrNull(quantity);
    if (value != null && (!Number.isFinite(value) || value <= 0)) return void act(async () => { throw new Error('Quantidade inválida.'); }, { tables: [] });
    if (value == null && !text.trim()) return void act(async () => { throw new Error('Sem quantidade numérica, informe a medida textual (ex.: “a gosto”).'); }, { tables: [] });
    await act(
      () => store.update('recipe_ingredients', { id: ingredient.id }, { quantity: value, unit: value == null ? null : unit.trim() || null, quantity_text: value == null ? text.trim() : null, display_name: name.trim() || ingredient.display_name }),
      { tables: [...TABLES], success: 'Ingrediente atualizado' },
    );
  }

  return (
    <div className="editrow">
      <input className="field" inputMode="decimal" aria-label="Quantidade" placeholder="qtd." value={quantity} onChange={(e) => setQuantity(e.target.value)} />
      {quantity.trim() ? (
        <input className="field" aria-label="Unidade" placeholder="unidade" value={unit} onChange={(e) => setUnit(e.target.value)} />
      ) : (
        <input className="field" aria-label="Medida textual" placeholder="a gosto…" value={text} onChange={(e) => setText(e.target.value)} />
      )}
      <div className="namecol">
        <div className="row" style={{ flexWrap: 'nowrap' }}>
          <input className="field grow" aria-label="Ingrediente" value={name} onChange={(e) => setName(e.target.value)} />
          {dirty && <button type="button" className="btn dark sm" onClick={save}><Save /> Salvar</button>}
        </div>
        {ingredient.original_text && <div className="original">original{ingredient.source_page ? ` (p. ${ingredient.source_page})` : ''}: {ingredient.original_text}</div>}
        <div className="row" style={{ marginTop: 6 }}>
          {ingredient.needs_review && <span className="pill warn">conferir</span>}
          {ingredient.scaling !== 'linear' && <span className="pill muted">{ingredient.scaling === 'manual' ? 'ajuste com validação' : 'quantidade fixa'}</span>}
          {ingredient.household_note && <span className="pill muted">{ingredient.household_note}</span>}
        </div>
      </div>
    </div>
  );
}

function StepRow({ step, index }: { step: RecipeStep; index: number }) {
  const { store } = useSession();
  const act = useAdminAction();
  const [instruction, setInstruction] = useState(step.instruction);
  const dirty = instruction !== step.instruction;
  return (
    <div style={{ padding: '10px 0', borderBottom: '1px solid #f0efe9' }}>
      <div className="row" style={{ alignItems: 'flex-start', flexWrap: 'nowrap' }}>
        <span className="partnum" style={{ background: '#f1f0e7', color: 'var(--forest)' }}>{index + 1}</span>
        <textarea className="textarea grow" style={{ minHeight: 64 }} aria-label={`Etapa ${index + 1}`} value={instruction} onChange={(e) => setInstruction(e.target.value)} />
      </div>
      {step.original_text && step.original_text !== step.instruction && <div className="original" style={{ marginLeft: 40 }}>original{step.source_page ? ` (p. ${step.source_page})` : ''}: {step.original_text}</div>}
      {dirty && (
        <div className="row" style={{ marginLeft: 40, marginTop: 8 }}>
          <button type="button" className="btn dark sm" onClick={() => act(() => store.update('recipe_steps', { id: step.id }, { instruction: instruction.trim() }), { tables: [...TABLES], success: 'Etapa atualizada' })}><Save /> Salvar</button>
          <button type="button" className="btn outline sm" onClick={() => setInstruction(step.instruction)}>Desfazer</button>
        </div>
      )}
    </div>
  );
}

function FlagRow({ flag }: { flag: ReviewFlag }) {
  const { store, user } = useSession();
  const act = useAdminAction();
  const { ask } = useDialog();
  const Icon = flag.severity === 'blocker' ? TriangleAlert : flag.severity === 'warning' ? CircleAlert : Info;
  const resolved = Boolean(flag.resolved_at);
  return (
    <div className={`flag ${flag.severity} ${resolved ? 'resolved' : ''}`}>
      <Icon color={flag.severity === 'info' ? 'var(--green)' : flag.severity === 'blocker' ? 'var(--danger)' : '#b07a1e'} />
      <div className="grow">
        {flag.message}
        <div className="muted small" style={{ marginTop: 3 }}>
          {flag.entity}{flag.field ? ` · ${flag.field}` : ''}{flag.source_page ? ` · p. ${flag.source_page}` : ''}
          {flag.severity === 'info' ? ' · informativo (não bloqueia)' : ''}
          {resolved && flag.resolution_note ? ` · ${flag.resolution_note}` : ''}
        </div>
      </div>
      {resolved ? (
        <button type="button" className="btn outline sm" onClick={() => act(() => store.update('review_flags', { id: flag.id }, { resolved_at: null, resolved_by: null, resolution_note: null }), { tables: [...TABLES] })}><RotateCcw /> Reabrir</button>
      ) : (
        <button
          type="button"
          className="btn dark sm"
          onClick={async () => {
            const note = await ask({ title: 'Resolver ponto de revisão', message: flag.message, label: 'Como foi resolvido? (opcional)', defaultValue: 'Conferido com o PDF original', confirmLabel: 'Marcar como resolvido' });
            if (note === null) return;
            void act(() => store.update('review_flags', { id: flag.id }, { resolved_at: new Date().toISOString(), resolved_by: user?.id ?? null, resolution_note: note.trim() || null }), { tables: [...TABLES], success: 'Ponto resolvido' });
          }}
        >
          <Check /> Resolver
        </button>
      )}
    </div>
  );
}

function BasicsForm({ recipe }: { recipe: Recipe }) {
  const { store } = useSession();
  const act = useAdminAction();
  const [form, setForm] = useState({
    title: recipe.title,
    description: recipe.description ?? '',
    difficulty: recipe.difficulty ?? '',
    servings: recipe.servings != null ? String(recipe.servings) : '',
    prep_minutes: recipe.prep_minutes != null ? String(recipe.prep_minutes) : '',
    cover_image: recipe.cover_image ?? '',
    is_featured: recipe.is_featured,
  });
  useEffect(() => {
    setForm((f) => ({ ...f, title: recipe.title, is_featured: recipe.is_featured }));
  }, [recipe.title, recipe.is_featured]);
  const set = (key: keyof typeof form) => (event: { target: { value: string } }) => setForm((f) => ({ ...f, [key]: event.target.value }));

  async function save(event: FormEvent) {
    event.preventDefault();
    const servings = numberOrNull(form.servings);
    const prep = numberOrNull(form.prep_minutes);
    await act(
      () =>
        store.update('recipes', { id: recipe.id }, {
          title: form.title.trim() || recipe.title,
          description: form.description.trim() || null,
          difficulty: (form.difficulty || null) as Recipe['difficulty'],
          servings: servings != null && Number.isFinite(servings) && servings > 0 ? Math.round(servings) : null,
          prep_minutes: prep != null && Number.isFinite(prep) && prep > 0 ? Math.round(prep) : null,
          cover_image: form.cover_image.trim() || null,
          is_featured: form.is_featured,
        }),
      { tables: [...TABLES], success: 'Dados da receita salvos' },
    );
  }

  return (
    <form className="formgrid" onSubmit={save}>
      <div className="group full"><label htmlFor="r-title">Título</label><input id="r-title" className="field" value={form.title} onChange={set('title')} required /></div>
      <div className="group full"><label htmlFor="r-desc">Descrição</label><textarea id="r-desc" className="textarea" value={form.description} onChange={set('description')} /></div>
      <div className="group">
        <label htmlFor="r-diff">Dificuldade</label>
        <select id="r-diff" className="select" value={form.difficulty} onChange={set('difficulty')}>
          <option value="">Não informada no material</option><option value="facil">Fácil</option><option value="media">Média</option><option value="dificil">Difícil</option>
        </select>
      </div>
      <div className="group"><label htmlFor="r-serv">Porções</label><input id="r-serv" className="field" inputMode="numeric" placeholder="Não informado" value={form.servings} onChange={set('servings')} /></div>
      <div className="group"><label htmlFor="r-prep">Tempo de preparo (min)</label><input id="r-prep" className="field" inputMode="numeric" placeholder="Não informado" value={form.prep_minutes} onChange={set('prep_minutes')} /></div>
      <div className="group"><label htmlFor="r-cover">Imagem de capa (caminho ou URL)</label><input id="r-cover" className="field" placeholder="/images/…" value={form.cover_image} onChange={set('cover_image')} /></div>
      <label className="row full" style={{ cursor: 'pointer' }}>
        <input type="checkbox" className="check" checked={form.is_featured} onChange={(e) => setForm((f) => ({ ...f, is_featured: e.target.checked }))} /> Destacar na página inicial
      </label>
      <p className="muted small full">Preencha porções, dificuldade e tempo apenas se o material de origem informar. Campos vazios aparecem como “não informado”.</p>
      <div className="group full"><button type="submit" className="btn dark"><Save /> Salvar dados</button></div>
    </form>
  );
}

export default function AdminRecipeEditor() {
  const { id } = useParams<{ id: string }>();
  const { store } = useSession();
  const act = useAdminAction();
  const { rows: recipes, loading } = useTable('recipes', { eq: { id } });
  const recipe = recipes?.[0];
  const scope = recipe ? { eq: { recipe_id: recipe.id } } : null;
  const { rows: components } = useTable('recipe_components', scope);
  const { rows: ingredients } = useTable('recipe_ingredients', scope);
  const { rows: steps } = useTable('recipe_steps', scope);
  const { rows: stepIngredients } = useTable('recipe_step_ingredients', scope);
  const { rows: timers } = useTable('recipe_step_timers', scope);
  const { rows: notes } = useTable('recipe_notes', scope);
  const { rows: flags } = useTable('review_flags', scope);
  const { rows: documents } = useTable('source_documents', recipe?.source_document_id ? { eq: { id: recipe.source_document_id } } : null);
  const { rows: collections } = useTable('collections', recipe ? { eq: { id: recipe.collection_id } } : null);

  const detail = useMemo(
    () => recipe && assembleRecipeDetail(recipe, { components: components ?? [], ingredients: ingredients ?? [], steps: steps ?? [], stepIngredients: stepIngredients ?? [], timers: timers ?? [], notes: notes ?? [], tags: [] }),
    [recipe, components, ingredients, steps, stepIngredients, timers, notes],
  );

  if (loading) return <Loading />;
  if (!recipe || !detail) return <Empty icon={X} title="Receita não encontrada" action={<Link href="/admin/receitas" className="btn dark">Voltar à lista</Link>} />;

  const document = documents?.[0];
  const open = (flags ?? []).filter((f) => !f.resolved_at && f.severity !== 'info');
  const sortedFlags = [...(flags ?? [])].sort((a, b) => Number(Boolean(a.resolved_at)) - Number(Boolean(b.resolved_at)) || (a.severity === 'info' ? 1 : 0) - (b.severity === 'info' ? 1 : 0));
  const structured = recipe.content_state === 'structured';
  const checks = [
    { ok: structured, label: 'Ficha estruturada a partir do PDF' },
    { ok: structured && open.length === 0, label: open.length ? `${open.length} ponto(s) de revisão em aberto` : 'Pontos de revisão resolvidos' },
    { ok: Boolean(recipe.reviewed_at), label: recipe.reviewed_at ? 'Aprovada na revisão' : 'Aprovação da revisão' },
    { ok: document?.commercial_permission === 'confirmed', label: `Permissão comercial do material: ${PERMISSION_LABELS[document?.commercial_permission ?? 'unknown']}` },
  ];

  return (
    <>
      <div className="spread" style={{ marginBottom: 14, flexWrap: 'wrap' }}>
        <Link href="/admin/receitas" className="textbtn">← Receitas</Link>
        <Link href={`/receitas/${recipe.slug}`} className="btn outline sm"><Eye /> Ver a ficha no app</Link>
      </div>
      <div className="pagehead">
        <div className="grow">
          <div className="eyebrow">{collections?.[0]?.name} · {pageRange(recipe.source_page_start, recipe.source_page_end) ?? 'página a confirmar'}</div>
          <h1>{recipe.title}</h1>
          <p className="sub">Edite os dados, ingredientes e modo de preparo abaixo. As informações originais são preservadas para conferência.</p>
          {recipe.original_title && recipe.original_title !== recipe.title && <p className="sub">Título original: {recipe.original_title}{recipe.original_language !== 'pt-BR' ? ` (${recipe.original_language})` : ''}</p>}
        </div>
        <StatusPill status={recipe.status} />
      </div>

      <details className="panel" style={{ marginTop: 18 }}>
        <summary style={{ cursor: 'pointer', fontWeight: 700, color: 'var(--forest)' }}>
          Publicação e conferência da receita
          <span className="muted small" style={{ display: 'block', fontWeight: 400, marginTop: 4 }}>
            Abra somente quando precisar conferir autorização, revisão e liberação para assinantes.
          </span>
        </summary>
        <div style={{ marginTop: 18 }}>
        <div className="twocol">
          <section className="panel">
            <div className="eyebrow">Publicação</div>
            <h2 style={{ margin: '6px 0 14px' }}>Requisitos para entrar no ar</h2>
            <ul className="checklist">
              {checks.map((check) => (
                <li key={check.label} className={check.ok ? 'ok' : ''}><span className="mark">{check.ok ? <Check /> : <X />}</span><div>{check.label}</div></li>
              ))}
            </ul>
            <hr className="divider" />
            {recipe.status === 'pending_permission' ? (
              <Notice>Esta receita está bloqueada até a permissão comercial do documento ser confirmada em <Link href="/admin/documentos"><b>Documentos</b></Link>.</Notice>
            ) : (
              <div className="row">
                {statusActions(recipe.status).map((action) => (
                  <button key={action.to} type="button" className={`btn sm ${action.tone === 'primary' ? 'primary' : action.tone === 'danger' ? 'danger' : 'outline'}`}
                    onClick={() => act(() => store.update('recipes', { id: recipe.id }, { status: action.to }), { tables: [...TABLES], success: `Situação: ${action.label}` })}>
                    {action.label}
                  </button>
                ))}
              </div>
            )}
            {document && (
              <p className="muted small" style={{ marginTop: 12 }}>
                Documento: <Link href="/admin/documentos"><b>{document.title}</b></Link>{document.author ? ` — ${document.author}` : ''}.
              </p>
            )}
          </section>
  
          <section className="panel">
            <div className="eyebrow">Revisão humana</div>
            <h2 style={{ margin: '6px 0 14px' }}>Pontos de revisão</h2>
            {sortedFlags.length ? (
              <div className="stack">{sortedFlags.map((flag) => <FlagRow key={flag.id} flag={flag} />)}</div>
            ) : (
              <p className="sub">Nenhum ponto de revisão registrado para esta receita.</p>
            )}
          </section>
        </div>
        </div>
      </details>

      <section className="panel" style={{ marginTop: 18 }}>
        <div className="eyebrow">Dados gerais</div>
        <h2 style={{ margin: '6px 0 14px' }}>Sobre a receita</h2>
        <BasicsForm key={recipe.id} recipe={recipe} />
      </section>

      {structured ? (
        detail.parts.map((part) => (
          <section className="panel" style={{ marginTop: 18 }} key={part.component.id}>
            <div className="eyebrow">{ROLE_LABELS[part.component.role] ?? 'Parte'} · {pageRange(part.component.source_page_start, part.component.source_page_end) ?? ''}</div>
            <h2 style={{ margin: '6px 0 14px' }}>{part.component.title}</h2>
            <div className="twocol">
              <div>
                <div className="label" style={{ marginBottom: 6 }}>Ingredientes ({part.ingredients.length})</div>
                {part.ingredients.map((ingredient) => <IngredientRow key={`${ingredient.id}:${ingredient.updated_at}`} ingredient={ingredient} />)}
              </div>
              <div>
                <div className="label" style={{ marginBottom: 6 }}>Etapas ({part.steps.length})</div>
                {part.steps.map((step, index) => (
                  <div key={`${step.id}:${step.updated_at}`}>
                    <StepRow step={step} index={index} />
                    {step.timers.map((timer) => (
                      <div key={timer.id} className="original" style={{ marginLeft: 40 }}>
                        ⏱ {timer.label}: {timer.is_minimum ? 'mínimo de ' : ''}{formatDuration(timer.duration_seconds)}{timer.original_text ? ` — trecho original: “${timer.original_text}”` : ''}
                      </div>
                    ))}
                  </div>
                ))}
              </div>
            </div>
          </section>
        ))
      ) : (
        <div style={{ marginTop: 18 }}>
          <Empty icon={Info} title="Ficha aguardando o PDF">
            Este item foi catalogado pelo título e pela página do material. Quando o PDF chegar, a ficha (ingredientes, etapas e tempos) é estruturada a partir do original e entra aqui para revisão — nada é preenchido por suposição.
          </Empty>
        </div>
      )}
    </>
  );
}
