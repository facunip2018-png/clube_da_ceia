'use client';

import Image from 'next/image';
import Link from 'next/link';
import { useEffect, useMemo, useState } from 'react';
import { ArrowRight, BookOpen, CalendarHeart, ChefHat, Hourglass, Layers, Play, ShoppingBasket, Sparkles, Timer, Trophy } from 'lucide-react';
import { useCatalog, useFavoriteIds, useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { CollectionCard, RecipeCard } from '@/components/cards';
import { CardSkeletons, Empty, ErrorState, Notice, usePageTitle } from '@/components/ui';
import { daysUntil } from '@/lib/schedule';
import { formatDate } from '@/lib/format';

const TOOLS = [
  { href: '/minha-ceia', icon: CalendarHeart, title: 'Minha ceia', text: 'Cardápio, cronograma e checklist.' },
  { href: '/lista', icon: ShoppingBasket, title: 'Lista de compras', text: 'Ingredientes somados por categoria.' },
  { href: '/chef', icon: Sparkles, title: 'Chef IA', text: 'Tire dúvidas sobre as receitas.' },
  { href: '/desafios', icon: Trophy, title: 'Desafios', text: 'Pontos e medalhas da temporada.' },
  { href: '/temporizadores', icon: Timer, title: 'Temporizadores', text: 'Vários tempos ao mesmo tempo.' },
];

/** Próxima data festiva (Natal até 25/12; depois, a virada). */
function nextCelebration(today: Date): { label: string; days: number } {
  const year = today.getFullYear();
  const christmas = daysUntil(`${year}-12-25`, today);
  if (christmas >= 0) return { label: christmas === 0 ? 'Feliz Natal!' : `faltam ${christmas} dias para o Natal`, days: christmas };
  const newYear = daysUntil(`${year + 1}-01-01`, today);
  return { label: newYear === 0 ? 'Feliz Ano-Novo!' : `faltam ${newYear} dias para o Ano-Novo`, days: newYear };
}

export default function HomePage() {
  usePageTitle('Início');
  const { user, access, ready } = useSession();
  const { summaries, recipes, collections, stats, loading, error } = useCatalog();
  const favorites = useFavoriteIds();
  const { rows: plans } = useTable('meal_plans', user ? { eq: { status: 'active' }, order: [['event_date', 'asc']] } : null);
  const { rows: sessions } = useTable('cooking_sessions', user ? { eq: { status: 'active' }, order: [['updated_at', 'desc']], limit: 1 } : null);
  const [celebration, setCelebration] = useState<string | null>(null);
  useEffect(() => setCelebration(nextCelebration(new Date()).label), []);

  const published = useMemo(() => recipes.filter((r) => r.status === 'published'), [recipes]);
  const inPreparation = stats.reduce((sum, s) => sum + s.in_preparation, 0);
  const featured = useMemo(() => {
    const pool = access.is_admin ? recipes.filter((r) => r.content_state === 'structured') : published;
    return [...pool].sort((a, b) => Number(b.is_featured) - Number(a.is_featured)).slice(0, 4);
  }, [access.is_admin, recipes, published]);
  const plan = plans?.find((p) => p.event_date && daysUntil(p.event_date) >= 0) ?? plans?.[0];
  const session = sessions?.[0];
  const sessionRecipe = session ? recipes.find((r) => r.id === session.recipe_id) : null;
  const collectionOf = (id: string) => collections.find((c) => c.id === id) ?? null;

  return (
    <>
      <section className="hero">
        <Image src="/images/hero-ceia.jpg" alt="" fill priority sizes="(max-width: 900px) 100vw, 80vw" className="hero-img" />
        <div className="hero-copy">
          <div className="eyebrow">✦ {celebration ?? 'uma temporada de sabores'}</div>
          <h1>As melhores memórias começam à mesa.</h1>
          <p>Descubra as coleções da temporada, encontre sua próxima sobremesa favorita e organize cada detalhe da ceia com o Clube.</p>
          <div className="heroactions">
            <Link href="/colecoes" className="btn primary">Explorar coleções <ArrowRight /></Link>
            <Link href="/minha-ceia" className="btn light">Planejar minha ceia</Link>
          </div>
        </div>
      </section>

      <div className="stats">
        <div className="stat">
          <div className="stat-icon"><ChefHat /></div>
          <div><b>{loading ? '–' : published.length}</b><small>{published.length === 1 ? 'receita disponível' : 'receitas disponíveis'}</small></div>
        </div>
        <div className="stat">
          <div className="stat-icon"><Layers /></div>
          <div><b>{loading ? '–' : collections.length}</b><small>coleções na temporada</small></div>
        </div>
        <div className="stat">
          <div className="stat-icon"><Hourglass /></div>
          <div><b>{loading ? '–' : inPreparation}</b><small>em curadoria</small></div>
        </div>
      </div>

      {ready && access.is_admin && !loading && published.length === 0 && (
        <div style={{ marginTop: 16 }}>
          <Notice>
            <b>Nenhuma receita está no ar ainda.</b> Como administradora, você já enxerga as fichas em revisão; as clientes só verão o que for publicado.{' '}
            <Link href="/admin"><b>Abrir o guia de publicação →</b></Link>
          </Notice>
        </div>
      )}

      {session && sessionRecipe && (
        <div className="calc" style={{ marginTop: 16 }}>
          <div>
            <div className="eyebrow">Continue de onde parou</div>
            <h3 style={{ marginTop: 4 }}>{sessionRecipe.title}</h3>
            <span className="muted small">Etapa {session.current_step + 1} em andamento</span>
          </div>
          <Link href={`/cozinhar/${sessionRecipe.slug}`} className="btn dark"><Play /> Continuar cozinhando</Link>
        </div>
      )}

      {ready && user && access.has_access && (
        <div className="eventbox" style={{ marginTop: 16 }}>
          {plan?.event_date ? (
            <>
              <div className="datebox">
                <b>{formatDate(plan.event_date, { day: '2-digit' })}</b>
                <small>{formatDate(plan.event_date, { month: 'short' }).replace('.', '')}</small>
              </div>
              <div className="grow">
                <b>{plan.title}</b>
                <div className="muted small">
                  {daysUntil(plan.event_date) > 0 ? `Faltam ${daysUntil(plan.event_date)} dias` : daysUntil(plan.event_date) === 0 ? 'É hoje!' : 'Evento realizado'} · {plan.guests} convidados
                </div>
              </div>
              <Link href="/minha-ceia" className="btn outline sm">Abrir planejamento</Link>
            </>
          ) : (
            <>
              <div className="stat-icon"><CalendarHeart /></div>
              <div className="grow">
                <b>Sua ceia ainda não tem data marcada</b>
                <div className="muted small">Monte o cardápio e receba cronograma e checklist.</div>
              </div>
              <Link href="/minha-ceia" className="btn dark sm">Planejar agora</Link>
            </>
          )}
        </div>
      )}

      <div className="sectionhead">
        <div>
          <div className="eyebrow">Seu caderno gastronômico</div>
          <h2>Explore por coleção</h2>
          <p className="sub">Cada coleção reúne as preparações de um material original.</p>
        </div>
        <Link href="/colecoes" className="textbtn">Ver catálogo completo <ArrowRight /></Link>
      </div>
      {error ? (
        <ErrorState error={error} />
      ) : (
        <div className="collection-grid">
          {loading ? <CardSkeletons count={6} height={270} /> : summaries.map((s, i) => <CollectionCard key={s.collection.id} summary={s} priority={i < 3} />)}
        </div>
      )}

      <div className="sectionhead">
        <div>
          <div className="eyebrow">Para começar</div>
          <h2>Receitas em destaque</h2>
        </div>
      </div>
      {loading ? (
        <div className="recipegrid"><CardSkeletons count={4} /></div>
      ) : featured.length ? (
        <div className="recipegrid">
          {featured.map((recipe) => (
            <RecipeCard key={recipe.id} recipe={recipe} collection={collectionOf(recipe.collection_id)} favorite={favorites.has(recipe.id)} showStatus={access.is_admin} />
          ))}
        </div>
      ) : (
        <Empty icon={BookOpen} title="As primeiras receitas estão chegando">
          Nossa curadoria está revisando cada ficha a partir do material original. Assim que forem aprovadas, elas aparecem aqui.
        </Empty>
      )}

      <div className="sectionhead">
        <div>
          <div className="eyebrow">Ferramentas do Clube</div>
          <h2>Tudo para organizar a ceia</h2>
        </div>
      </div>
      <div className="challengegrid">
        {TOOLS.map((tool) => (
          <Link key={tool.href} href={tool.href} className="challenge" style={{ flexDirection: 'row', alignItems: 'center', gap: 14 }}>
            <div className="challengeicon" style={{ margin: 0, flex: 'none' }}><tool.icon /></div>
            <div className="grow">
              <h3>{tool.title}</h3>
              <p>{tool.text}</p>
            </div>
            <ArrowRight size={18} color="var(--green)" />
          </Link>
        ))}
      </div>
    </>
  );
}
