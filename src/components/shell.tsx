'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useState, type FormEvent, type ReactNode } from 'react';
import { BookOpen, BookOpenText, CalendarHeart, House, Search, Settings, ShoppingBasket, Sparkles, Timer, Trophy, User, type LucideIcon } from 'lucide-react';
import { useSession } from '@/data/session';
import { useTable } from '@/data/hooks';
import { formatDate, initials } from '@/lib/format';
import type { Persona } from '@/data/local-store';
import { TimerDock, useTimers } from './timers';
import { useDialog } from './dialogs';

interface NavItem {
  href: string;
  label: string;
  short?: string;
  icon: LucideIcon;
}

const SPACE: NavItem[] = [
  { href: '/', label: 'Início', icon: House },
  { href: '/colecoes', label: 'Coleções e receitas', short: 'Coleções', icon: BookOpen },
  { href: '/minha-ceia', label: 'Minha ceia', icon: CalendarHeart },
  { href: '/lista', label: 'Lista de compras', icon: ShoppingBasket },
  { href: '/chef', label: 'Chef IA', icon: Sparkles },
  { href: '/desafios', label: 'Desafios', icon: Trophy },
  { href: '/materiais', label: 'Guias e dicas', icon: BookOpenText },
];
const ACCOUNT: NavItem[] = [
  { href: '/temporizadores', label: 'Temporizadores', icon: Timer },
  { href: '/perfil', label: 'Meu perfil', short: 'Perfil', icon: User },
];
const ADMIN: NavItem = { href: '/admin', label: 'Painel admin', icon: Settings };
const MOBILE = [SPACE[0], SPACE[1], SPACE[2], SPACE[4], ACCOUNT[1]];

const isActive = (pathname: string, href: string) =>
  href === '/' ? pathname === '/' : pathname === href || pathname.startsWith(`${href}/`) || (href === '/colecoes' && pathname.startsWith('/receitas'));

const PERSONAS: { id: Persona; label: string }[] = [
  { id: 'admin', label: 'Administradora' },
  { id: 'member', label: 'Cliente' },
  { id: 'visitor', label: 'Visitante' },
];

function DemoBar() {
  const { persona, setPersona, resetDemo } = useSession();
  const { confirm } = useDialog();
  return (
    <div className="demobar noprint">
      <b>DEMONSTRAÇÃO</b>
      <span className="hide-m">Ver como:</span>
      <div className="seg" role="group" aria-label="Perfil de demonstração">
        {PERSONAS.map((p) => (
          <button key={p.id} type="button" className={persona === p.id ? 'active' : ''} onClick={() => setPersona(p.id)} aria-pressed={persona === p.id}>
            {p.label}
          </button>
        ))}
      </div>
      <button type="button" className="link right" onClick={async () => (await confirm({ title: 'Reiniciar a demonstração?', message: 'Tudo o que foi feito nesta demonstração (publicações, planejamentos, listas) será apagado deste navegador.', confirmLabel: 'Reiniciar', danger: true })) && resetDemo()}>
        Reiniciar<span className="hide-m"> demonstração</span>
      </button>
    </div>
  );
}

function SeasonCard() {
  const { access, ready } = useSession();
  const { rows: seasons } = useTable('seasons', { order: [['created_at', 'desc']], limit: 1 });
  const season = seasons?.[0];
  if (ready && access.has_access && access.season_name) {
    return (
      <div className="season">
        <small>✦ sua temporada</small>
        <strong>{access.season_name}</strong>
        <span>{access.access_until ? `Acesso liberado até ${formatDate(access.access_until, { day: '2-digit', month: 'long' })}.` : 'Acesso liberado.'}</span>
      </div>
    );
  }
  return (
    <div className="season">
      <small>✦ temporada</small>
      <strong>{season?.name ?? 'Natal & Ano-Novo'}</strong>
      <span>Coleções especiais para preparar, organizar e celebrar.</span>
      {ready && !access.has_access && <Link href="/acesso">Liberar meu acesso →</Link>}
    </div>
  );
}

export function AppShell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const { mode, user, access } = useSession();
  const { timers } = useTimers();
  const [query, setQuery] = useState('');
  const all = [...SPACE, ...ACCOUNT, ADMIN];
  const current = all.find((item) => item.href !== '/' && isActive(pathname, item.href)) ?? (pathname === '/acesso' ? { label: 'Acesso da temporada' } : SPACE[0]);
  const activeTimers = timers.filter((t) => t.status !== 'paused').length;

  function onSearch(event: FormEvent) {
    event.preventDefault();
    const q = query.trim();
    router.push(q ? `/colecoes?q=${encodeURIComponent(q)}` : '/colecoes');
  }

  const link = (item: NavItem, badge?: string) => (
    <Link key={item.href} href={item.href} className={isActive(pathname, item.href) ? 'active' : ''} aria-current={isActive(pathname, item.href) ? 'page' : undefined}>
      <item.icon aria-hidden />
      {item.label}
      {badge && <span className="badge">{badge}</span>}
    </Link>
  );

  return (
    <>
      <aside className="sidebar noprint">
        <Link href="/" className="brand" aria-label="Clube da Ceia Perfeita — início">
          <div className="brandmark">✦</div>
          <div>
            <div className="brandtitle">CLUBE DA CEIA<br />PERFEITA</div>
            <div className="brandsub">NATAL &amp; ANO-NOVO</div>
          </div>
        </Link>
        <div className="navlabel">Seu espaço</div>
        <nav className="nav" aria-label="Principal">{SPACE.map((item) => link(item))}</nav>
        <div className="navlabel">Conta</div>
        <nav className="nav" aria-label="Conta">
          {ACCOUNT.map((item) => link(item, item.href === '/temporizadores' && activeTimers ? String(activeTimers) : undefined))}
          {access.is_admin && link(ADMIN, mode === 'demo' ? 'DEMO' : undefined)}
        </nav>
        <div style={{ height: 18 }} />
        <SeasonCard />
      </aside>

      <main className="main">
        {mode === 'demo' && <DemoBar />}
        <header className="topbar noprint">
          <div className="crumb">
            <Link href="/" className="mobile-brand" aria-label="Início">
              <span className="brandmark" style={{ color: 'var(--gold)' }}>✦</span> Ceia Perfeita
            </Link>
            <span className="desktop">Clube</span>
            <span className="sep desktop">/</span>
            <b className="desktop">{current.label}</b>
          </div>
          <div className="topright">
            <form className="search" role="search" onSubmit={onSearch}>
              <Search aria-hidden />
              <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Buscar uma receita…" aria-label="Buscar uma receita" />
            </form>
            <Link href="/lista" className="iconbtn" aria-label="Lista de compras"><ShoppingBasket /></Link>
            <Link href="/temporizadores" className="iconbtn" aria-label={activeTimers ? `Temporizadores (${activeTimers} em andamento)` : 'Temporizadores'}>
              <Timer />
              {activeTimers > 0 && <span className="dot" />}
            </Link>
            <Link href="/perfil" className="avatar" aria-label="Meu perfil">{user ? initials(user.name) : <User size={17} />}</Link>
          </div>
        </header>
        <div className="content">
          <div className="page" key={pathname}>{children}</div>
          <div className="footer noprint">CLUBE DA CEIA PERFEITA · Natal &amp; Ano-Novo</div>
        </div>
      </main>

      <nav className="mobilenav noprint" aria-label="Navegação">
        {MOBILE.map((item) => (
          <Link key={item.href} href={item.href} className={isActive(pathname, item.href) ? 'active' : ''} aria-current={isActive(pathname, item.href) ? 'page' : undefined}>
            <item.icon aria-hidden />
            {item.short ?? item.label}
          </Link>
        ))}
      </nav>
      <TimerDock />
    </>
  );
}
