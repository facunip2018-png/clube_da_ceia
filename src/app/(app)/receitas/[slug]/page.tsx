'use client';

import Link from 'next/link';
import { useParams } from 'next/navigation';
import { useState } from 'react';
import {
  BookMarked, CalendarHeart, ChefHat, Clock, Download, Heart, Hourglass, Lightbulb, Play, RotateCcw, Scale, SearchX, Settings, ShoppingBasket,
  Sparkles, Timer, TriangleAlert, Utensils,
} from 'lucide-react';
import { useFavoriteIds, useIngredientCatalog, useRecipeDetail, useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { addRecipeToShoppingList, toggleFavorite } from '@/data/actions';
import { StatusPill } from '@/components/cards';
import { AddToPlanSheet } from '@/components/add-to-plan';
import { Paywall } from '@/components/gates';
import { useTimers } from '@/components/timers';
import { useToast } from '@/components/toast';
import { Cover, Empty, Loading, Notice, Stepper, usePageTitle } from '@/components/ui';
import { describeYield, factorFromTarget, scaleIngredient, targetFromFactor, yieldControl } from '@/lib/scaling';
import { DIFFICULTY_LABELS, knownTimes } from '@/lib/recipe-view';
import { formatClock, formatDuration, formatMinutes, formatQuantity, pageRange } from '@/lib/format';
import { remainingMs } from '@/lib/timers';
import type { RecipeDetail, RecipeStepTimer } from '@/lib/types';

function StepTimer({ timer, detail }: { timer: RecipeStepTimer; detail: RecipeDetail }) {
  const timers = useTimers();
  const running = timers.findBySource(timer.id);
  const label = `${timer.is_minimum ? 'mín. ' : ''}${formatDuration(timer.duration_seconds)}`;
  if (running && running.status !== 'done') {
    return (
      <Link href="/temporizadores" className="timerchip">
        <Timer /> {timer.label} · {formatClock(remainingMs(running, timers.now))}
      </Link>
    );
  }
  return (
    <button
      type="button"
      className="timerchip"
      onClick={() =>
        timers.start({
          label: timer.label, durationMs: timer.duration_seconds * 1000, recipeId: detail.recipe.id, recipeTitle: detail.recipe.title,
          recipeSlug: detail.recipe.slug, stepId: timer.step_id, sourceTimerId: timer.id, isMinimum: timer.is_minimum,
        })
      }
    >
      <Timer /> Iniciar {timer.label.toLocaleLowerCase('pt-BR')} · {label}
      {timer.temperature_c ? ` · ${timer.temperature_c} °C` : ''}
    </button>
  );
}

export default function RecipePage() {
  const { slug } = useParams<{ slug: string }>();
  const { user, access, store, ready, supabase } = useSession();
  const { toast, fail } = useToast();
  const { rows, loading } = useTable('recipes', { eq: { slug } });
  const recipe = rows?.[0] ?? null;
  const { detail, loading: loadingDetail } = useRecipeDetail(recipe);
  const favorites = useFavoriteIds();
  const catalog = useIngredientCatalog();
  const [factor, setFactor] = useState(1);
  const [planning, setPlanning] = useState(false);
  const [busy, setBusy] = useState(false);
  const [downloadingPdf, setDownloadingPdf] = useState(false);
  usePageTitle(recipe?.title ?? 'Receita');

  if (loading || !ready) return <Loading />;
  if (!recipe || !detail) {
    return (
      <Empty icon={SearchX} title="Receita não encontrada" action={<Link href="/colecoes" className="btn dark">Voltar ao catálogo</Link>}>
        Esta receita não existe ou ainda não foi publicada.
      </Empty>
    );
  }

  const collection = detail.collection;
  const control = yieldControl(recipe);
  const times = knownTimes(recipe);
  const isFavorite = favorites.has(recipe.id);
  const canUse = access.has_access && detail.hasContent;
  const pages = pageRange(recipe.source_page_start, recipe.source_page_end);
  const cover = recipe.cover_image ?? collection?.cover_image ?? null;
  const adjusted = Math.abs(factor - 1) > 1e-9;

  async function onFavorite() {
    try {
      const now = await toggleFavorite(store, recipe!.id, isFavorite);
      toast(now ? 'Salva nas suas favoritas' : 'Removida das favoritas');
    } catch (error) {
      fail(error);
    }
  }

  async function onAddToList() {
    setBusy(true);
    try {
      const count = await addRecipeToShoppingList(store, detail!, factor, catalog);
      toast(`${count} ${count === 1 ? 'item' : 'itens'} na lista de compras`, { action: { label: 'Ver lista', onClick: () => window.location.assign('/lista') } });
    } catch (error) {
      fail(error);
    } finally {
      setBusy(false);
    }
  }

  async function onDownloadOriginalPdf() {
    const source = detail?.source;
    if (!supabase || !access.has_access || !source?.storage_path) return;
    setDownloadingPdf(true);
    try {
      const { data, error } = await supabase.storage
        .from('source-documents')
        .createSignedUrl(source.storage_path, 60, { download: source.file_name ?? true });
      if (error) throw error;
      window.location.assign(data.signedUrl);
    } catch (error) {
      fail(error);
    } finally {
      setDownloadingPdf(false);
    }
  }

  return (
    <>
      <div className="spread" style={{ marginBottom: 16 }}>
        <Link href={collection ? `/colecoes/${collection.slug}` : '/colecoes'} className="textbtn">← {collection?.name ?? 'Voltar ao catálogo'}</Link>
        <div className="row">
          {access.is_admin && <StatusPill status={recipe.status} />}
          {access.is_admin && <Link href={`/admin/receitas/${recipe.id}`} className="btn outline sm"><Settings /> Revisar ficha</Link>}
        </div>
      </div>

      <div className="detailgrid">
        <div className="detailphoto">
          {cover ? <Cover src={cover} alt={recipe.title} sizes="(max-width: 1100px) 100vw, 50vw" priority /> : <div className="photo placeholder" style={{ height: '100%' }}><Utensils /></div>}
        </div>

        <div>
          <div className="eyebrow">{collection?.name ?? 'Receita'}{recipe.kind !== 'recipe' ? ` · ${recipe.kind === 'component' ? 'componente' : 'variação'}` : ''}</div>
          <h1 style={{ margin: '8px 0 10px' }}>{recipe.title}</h1>
          {recipe.description && <p className="sub">{recipe.description}</p>}

          <div className="metricrow">
            {recipe.yield_text && (
              <div className="metric"><Scale /><div><small>Rendimento</small><b>{recipe.yield_text}</b></div></div>
            )}
            {times.map((time) => (
              <div className="metric" key={time.label}><Clock /><div><small>{time.label}</small><b>{time.minimum ? 'mín. ' : ''}{formatMinutes(time.minutes)}</b></div></div>
            ))}
            {recipe.difficulty && <div className="metric"><ChefHat /><div><small>Dificuldade</small><b>{DIFFICULTY_LABELS[recipe.difficulty]}</b></div></div>}
            {recipe.servings != null && <div className="metric"><Utensils /><div><small>Porções</small><b>{recipe.servings}</b></div></div>}
          </div>

          {canUse ? (
            <div className="actions">
              {detail.source?.storage_path && (
                <button type="button" className="btn outline" onClick={onDownloadOriginalPdf} disabled={downloadingPdf}>
                  <Download /> {downloadingPdf ? 'Preparando PDF…' : 'Baixar PDF original'}
                </button>
              )}
              <Link href={`/cozinhar/${recipe.slug}${adjusted ? `?f=${factor}` : ''}`} className="btn primary wide"><Play /> Iniciar modo cozinheiro</Link>
              <button type="button" className="btn dark" onClick={() => setPlanning(true)}><CalendarHeart /> Adicionar à minha ceia</button>
              <button type="button" className="btn dark" onClick={onAddToList} disabled={busy}><ShoppingBasket /> Ingredientes na lista</button>
              <button type="button" className="btn outline" onClick={onFavorite} aria-pressed={isFavorite}>
                <Heart fill={isFavorite ? 'currentColor' : 'none'} color={isFavorite ? '#b8413a' : undefined} /> {isFavorite ? 'Nas favoritas' : 'Salvar nas favoritas'}
              </button>
              <Link href={`/chef?receita=${recipe.slug}`} className="btn outline"><Sparkles /> Perguntar ao Chef</Link>
            </div>
          ) : !access.has_access ? (
            <div style={{ marginTop: 18 }}><Paywall title="Ficha completa para membros da temporada" /></div>
          ) : (
            <div className="empty" style={{ marginTop: 18, textAlign: 'left', justifyItems: 'start' }}>
              <div className="ico"><Hourglass /></div>
              <h3>Ficha interativa em preparação</h3>
              <p className="sub">
                Esta preparação está identificada no material de origem{pages ? ` (${pages})` : ''}. Ingredientes, quantidades, etapas e temporizadores serão estruturados a partir do PDF e revisados antes da publicação.
              </p>
              <p className="sub small">Não exibimos ingredientes ou instruções inventados.</p>
              {user && recipe.status === 'published' && (
                <button type="button" className="btn outline sm" onClick={onFavorite}><Heart /> {isFavorite ? 'Nas favoritas' : 'Salvar nas favoritas'}</button>
              )}
            </div>
          )}
        </div>
      </div>

      {access.has_access && loadingDetail && <div style={{ marginTop: 26 }}><Loading /></div>}

      {canUse && (
        <>
          <div className="twocol recipe-cols" style={{ marginTop: 30 }}>
            <section className="panel" aria-labelledby="ingredientes">
              <div className="eyebrow">O que vai</div>
              <h2 id="ingredientes" style={{ margin: '6px 0 14px' }}>Ingredientes</h2>

              <div className="calc" style={{ marginBottom: 18 }}>
                <div className="grow">
                  <h3>Calculadora de porções</h3>
                  <span className="muted small">
                    {control.mode === 'servings'
                      ? `A ficha rende ${recipe.servings} porções.`
                      : control.mode === 'yield'
                        ? `O material não informa porções: ajuste por ${control.unit}.`
                        : 'O material não informa rendimento: ajuste por receita.'}
                  </span>
                </div>
                <div className="row">
                  <Stepper
                    label="Quantidade"
                    value={targetFromFactor(control, factor)}
                    min={control.min}
                    max={control.max}
                    step={control.step}
                    onChange={(target) => setFactor(factorFromTarget(control, target))}
                    format={(value) => formatQuantity(value, control.unit)}
                  />
                  {adjusted && (
                    <button type="button" className="iconbtn" onClick={() => setFactor(1)} aria-label="Voltar à receita original" title="Receita original"><RotateCcw /></button>
                  )}
                </div>
              </div>
              {adjusted && (
                <div style={{ marginBottom: 14 }}>
                  <Notice icon={TriangleAlert}>
                    Quantidades ajustadas para <b>{describeYield(recipe, factor)}</b>. Só os valores numéricos foram multiplicados, sem conversão de unidades. Tempos e o tamanho do recipiente não mudam na mesma proporção.
                  </Notice>
                </div>
              )}

              {detail.parts.filter((p) => p.ingredients.length).map((part, index) => (
                <div className="part" key={part.component.id}>
                  <div className="parthead"><span className="partnum">{index + 1}</span><h3>{part.component.title}</h3></div>
                  <ul className="inglist">
                    {part.ingredients.map((ingredient) => {
                      const scaled = scaleIngredient(ingredient, factor);
                      return (
                        <li className="ing" key={ingredient.id}>
                          <span className={`qty ${scaled.quantity == null ? 'textual' : ''}`}>{scaled.text}</span>
                          <span className="name">
                            {ingredient.display_name}
                            {ingredient.preparation ? `, ${ingredient.preparation}` : ''}
                            {ingredient.is_optional ? ' (opcional)' : ''}
                            {scaled.householdNote && <span className="note">{scaled.householdNote}</span>}
                            {scaled.note && <span className={`note ${scaled.status === 'needs_validation' ? 'warn' : ''}`}>{scaled.note}</span>}
                          </span>
                        </li>
                      );
                    })}
                  </ul>
                </div>
              ))}
              {recipe.measure_note && <Notice tone="soft">{recipe.measure_note}</Notice>}
            </section>

            <section className="panel" aria-labelledby="preparo">
              <div className="eyebrow">Passo a passo</div>
              <h2 id="preparo" style={{ margin: '6px 0 14px' }}>Modo de preparo</h2>
              {detail.parts.filter((p) => p.steps.length).map((part, index) => (
                <div className="part" key={part.component.id}>
                  <div className="parthead"><span className="partnum">{index + 1}</span><h3>{part.component.title}</h3></div>
                  <ol className="steplist">
                    {part.steps.map((step) => (
                      <li className="step" key={step.id}>
                        <div>
                          <p>{step.instruction}</p>
                          {step.tip && <p className="muted small" style={{ marginTop: 4 }}>{step.tip}</p>}
                          {step.timers.map((timer) => <StepTimer key={timer.id} timer={timer} detail={detail} />)}
                        </div>
                      </li>
                    ))}
                  </ol>
                </div>
              ))}
              <Link href={`/cozinhar/${recipe.slug}${adjusted ? `?f=${factor}` : ''}`} className="btn dark block"><Play /> Cozinhar passo a passo</Link>
            </section>
          </div>

          {(detail.tips.length > 0 || detail.notes.length > 0 || detail.equipment.length > 0) && (
            <div className="twocol" style={{ marginTop: 22 }}>
              {(detail.tips.length > 0 || detail.notes.length > 0) && (
                <section className="panel">
                  <div className="eyebrow">Do material original</div>
                  <h2 style={{ margin: '6px 0 14px' }}>Dicas e observações</h2>
                  <div className="stack">
                    {detail.tips.map((tip) => (
                      <div className="tipcard" key={tip.id}><Lightbulb size={16} style={{ verticalAlign: -3, marginRight: 6, color: 'var(--gold-deep)' }} />{tip.body}</div>
                    ))}
                    {detail.notes.map((note) => (
                      <div key={note.id}>
                        {note.title && <b>{note.title}</b>}
                        <p className="sub">{note.body}</p>
                      </div>
                    ))}
                  </div>
                </section>
              )}
              {detail.equipment.length > 0 && (
                <section className="panel">
                  <div className="eyebrow">Tenha à mão</div>
                  <h2 style={{ margin: '6px 0 14px' }}>Utensílios</h2>
                  <div className="chips">
                    {detail.equipment.map((item) => <span className="pill" style={{ fontSize: 13, padding: '7px 12px' }} key={item.id}>{item.body}</span>)}
                  </div>
                </section>
              )}
            </div>
          )}
        </>
      )}

      {(detail.source || pages) && (
        <div className="sourcebox">
          <BookMarked />
          <div>
            <b>Fonte original:</b> {detail.source?.title ?? 'material de origem'}
            {detail.source?.author ? ` — ${detail.source.author}` : ''}
            {detail.source?.publisher ? ` (${detail.source.publisher})` : ''}
            {pages ? ` · ${pages}` : ''}.
            {recipe.original_language !== 'pt-BR' && ' Texto traduzido para o português a partir do original.'}
            {' '}Ingredientes, quantidades e etapas seguem o material, sem alterações.
          </div>
        </div>
      )}
      {planning && <AddToPlanSheet recipe={recipe} factor={factor} onClose={() => setPlanning(false)} />}
    </>
  );
}
