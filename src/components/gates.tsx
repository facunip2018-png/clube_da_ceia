'use client';

import Link from 'next/link';
import type { ReactNode } from 'react';
import { Check, KeyRound, Lock, ShieldCheck } from 'lucide-react';
import { useSession } from '@/data/session';
import { Empty, Loading } from './ui';

/** Convite para liberar o conteúdo da temporada. */
export function Paywall({ title = 'Conteúdo exclusivo da temporada', compact }: { title?: string; compact?: boolean }) {
  const { user, mode } = useSession();
  return (
    <div className="lockcard">
      <div className="eyebrow">✦ Clube da Ceia Perfeita</div>
      <h3>{title}</h3>
      <p>Com o acesso da temporada você abre as fichas completas e todas as ferramentas do Clube.</p>
      {!compact && (
        <ul>
          <li><Check /> Ingredientes, quantidades e modo de preparo</li>
          <li><Check /> Calculadora de porções e lista de compras</li>
          <li><Check /> Modo cozinheiro com temporizadores</li>
          <li><Check /> Planejador da ceia e Chef IA</li>
        </ul>
      )}
      <div className="row" style={{ marginTop: compact ? 14 : 0 }}>
        <Link href="/acesso" className="btn primary"><Lock /> Liberar meu acesso</Link>
        {!user && mode === 'supabase' && <Link href="/entrar" className="btn ghost" style={{ color: '#fff' }}>Já sou do Clube</Link>}
      </div>
    </div>
  );
}

/** Mostra o conteúdo apenas para quem está logado (e, se pedido, com acesso da temporada). */
export function Guard({ children, access = false, what }: { children: ReactNode; access?: boolean; what: string }) {
  const session = useSession();
  if (!session.ready) return <Loading />;
  if (!session.user) {
    return (
      <Empty
        icon={KeyRound}
        title="Entre para continuar"
        action={
          session.mode === 'demo' ? (
            <button type="button" className="btn dark" onClick={() => session.setPersona('member')}>Entrar como cliente (demonstração)</button>
          ) : (
            <div className="row" style={{ justifyContent: 'center' }}>
              <Link href="/entrar" className="btn dark">Entrar</Link>
              <Link href="/cadastro" className="btn outline">Criar conta</Link>
            </div>
          )
        }
      >
        {what} fica guardado na sua conta, só para você.
      </Empty>
    );
  }
  if (access && !session.access.has_access) return <Paywall title={`${what} faz parte do acesso da temporada`} />;
  return <>{children}</>;
}

export function AdminOnly({ children }: { children: ReactNode }) {
  const session = useSession();
  if (!session.ready) return <Loading />;
  if (!session.access.is_admin) {
    return (
      <Empty icon={ShieldCheck} title="Área restrita" action={<Link href="/" className="btn dark">Voltar ao início</Link>}>
        O painel administrativo é exclusivo para administradores do Clube.
      </Empty>
    );
  }
  return <>{children}</>;
}

export function SetupScreen() {
  return (
    <div className="authform" style={{ minHeight: '100dvh' }}>
      <div className="authcard" style={{ maxWidth: 560 }}>
        <div className="brandrow">
          <div className="brandmark">✦</div>
          <div>
            <div className="brandtitle" style={{ color: 'var(--forest)' }}>CLUBE DA CEIA PERFEITA</div>
            <div className="brandsub" style={{ color: 'var(--gold-deep)' }}>NATAL &amp; ANO-NOVO</div>
          </div>
        </div>
        <h1>Falta conectar o banco de dados.</h1>
        <p className="sub">
          O app está publicado, mas ainda não recebeu as chaves do Supabase. Por segurança, nenhum conteúdo é exibido até a configuração ser concluída.
        </p>
        <div className="panel stack">
          <div>
            <div className="eyebrow">Variáveis de ambiente</div>
            <p className="sub" style={{ marginTop: 6 }}>Defina na Vercel (Settings → Environment Variables) e faça um novo deploy:</p>
          </div>
          <div className="original">NEXT_PUBLIC_SUPABASE_URL=https://SEU-PROJETO.supabase.co{'\n'}NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sua-chave-publica</div>
          <p className="sub small">O passo a passo completo está em <b>docs/CONFIGURACAO.md</b> no repositório.</p>
        </div>
      </div>
    </div>
  );
}
