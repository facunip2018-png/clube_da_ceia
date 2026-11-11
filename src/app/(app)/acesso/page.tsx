'use client';

import Link from 'next/link';
import { useState } from 'react';
import { Check, CreditCard, Gift, Lock, ShieldCheck } from 'lucide-react';
import { invalidate, useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import type { LocalStore } from '@/data/local-store';
import { useToast } from '@/components/toast';
import { Loading, Notice, PageHead, usePageTitle } from '@/components/ui';
import { saleAvailability } from '@/lib/season';
import { formatDate, formatDateTime, formatMoney } from '@/lib/format';

const INCLUDED = [
  'Fichas completas das receitas publicadas na temporada',
  'Calculadora de porções e lista de compras inteligente',
  'Modo cozinheiro com temporizadores',
  'Planejador da ceia com cronograma e checklist',
  'Chef IA para tirar dúvidas sobre as receitas',
  'Desafios, pontos e medalhas',
];
const ORDER_STATUS: Record<string, string> = {
  pending: 'Aguardando pagamento', approved: 'Aprovado', rejected: 'Recusado', cancelled: 'Cancelado', refunded: 'Reembolsado',
  charged_back: 'Estornado', in_mediation: 'Em disputa', review_required: 'Em análise',
};

export default function AccessPage() {
  usePageTitle('Acesso da temporada');
  const { user, access, mode, store, refresh, ready } = useSession();
  const { toast, fail } = useToast();
  const { rows: seasons, loading } = useTable('seasons', { eq: { status: 'active' }, order: [['created_at', 'desc']], limit: 1 });
  const { rows: memberships } = useTable('memberships', user ? { eq: { user_id: user.id } } : null);
  const { rows: orders } = useTable('orders', user ? { eq: { user_id: user.id }, order: [['created_at', 'desc']], limit: 5 } : null);
  const [busy, setBusy] = useState(false);
  const [unavailable, setUnavailable] = useState<string | null>(null);
  const season = seasons?.[0] ?? null;
  const sale = saleAvailability(season);
  const locked = Boolean(season && memberships?.some((m) => m.season_id === season.id && m.status !== 'active' && m.admin_locked));

  async function buy() {
    setBusy(true);
    setUnavailable(null);
    try {
      if (mode === 'demo') {
        await (store as LocalStore).simulateApprovedPayment();
        await refresh();
        await invalidate('orders', 'memberships');
        toast('Pagamento simulado: acesso liberado nesta demonstração');
        return;
      }
      const response = await fetch('/api/checkout', { method: 'POST' });
      const data = (await response.json().catch(() => ({}))) as { init_point?: string; message?: string };
      if (!response.ok || !data.init_point) {
        setUnavailable(data.message ?? 'Não foi possível iniciar o pagamento agora.');
        return;
      }
      window.location.assign(data.init_point);
    } catch (error) {
      fail(error);
    } finally {
      setBusy(false);
    }
  }

  if (!ready || loading) return <Loading />;

  return (
    <>
      <PageHead eyebrow="Clube da Ceia Perfeita" title="Acesso da temporada." sub="Um pagamento único libera todo o conteúdo e as ferramentas do Clube durante a temporada." />
      <div className="twocol">
        <section className="lockcard">
          <div className="eyebrow">✦ {season?.name ?? 'Natal & Ano-Novo'}</div>
          <h3 style={{ fontSize: 28 }}>{access.has_access && !access.is_admin ? 'Seu acesso está liberado' : 'Tudo para a sua ceia perfeita'}</h3>
          <p>{season?.description ?? 'Coleções especiais para preparar, organizar e celebrar.'}</p>
          <ul>{INCLUDED.map((item) => <li key={item}><Check /> {item}</li>)}</ul>
          {season?.access_ends_at && <p className="small">Acesso válido até {formatDate(season.access_ends_at)}.</p>}
        </section>

        <section className="panel stack">
          {access.has_access && !access.is_admin ? (
            <>
              <div className="eyebrow">Tudo certo</div>
              <h2>Bom proveito, {user?.name.split(' ')[0]}!</h2>
              <p className="sub">Seu acesso à temporada {access.season_name} vale{access.access_until ? ` até ${formatDate(access.access_until)}` : ' durante toda a temporada'}.</p>
              <Link href="/colecoes" className="btn dark">Explorar as coleções</Link>
            </>
          ) : (
            <>
              <div className="eyebrow">Pagamento único</div>
              {sale.open && season ? (
                <>
                  <div><span className="serif" style={{ fontSize: 44, color: 'var(--forest)' }}>{formatMoney(season.price_cents ?? 0, season.currency)}</span><span className="muted"> · temporada inteira</span></div>
                  {access.is_admin && <Notice tone="soft">Você é administradora e já tem acesso a tudo. Esta é a página que as clientes veem.</Notice>}
                  {!user ? (
                    mode === 'demo' ? (
                      <Notice>Escolha o perfil <b>Cliente</b> na barra de demonstração para simular a compra.</Notice>
                    ) : (
                      <>
                        <p className="sub">Entre ou crie sua conta para concluir a compra. O acesso fica vinculado ao seu e-mail.</p>
                        <div className="row"><Link href="/cadastro?next=/acesso" className="btn primary">Criar conta</Link><Link href="/entrar?next=/acesso" className="btn outline">Já tenho conta</Link></div>
                      </>
                    )
                  ) : locked ? (
                    <Notice tone="danger">Seu acesso a esta temporada foi suspenso pela administração. Fale com o suporte do Clube antes de fazer um novo pagamento.</Notice>
                  ) : (
                    <button type="button" className="btn primary" onClick={buy} disabled={busy || access.is_admin}>
                      {mode === 'demo' ? <><Gift /> Simular pagamento aprovado (demonstração)</> : <><CreditCard /> Comprar com Mercado Pago</>}
                    </button>
                  )}
                  {unavailable && <Notice tone="danger">{unavailable}</Notice>}
                  <p className="muted small"><ShieldCheck size={14} style={{ verticalAlign: -2 }} /> O pagamento é processado pelo Mercado Pago. O acesso é liberado automaticamente após a confirmação — a página de retorno não libera nada por conta própria.</p>
                </>
              ) : (
                <>
                  <h2><Lock size={20} style={{ verticalAlign: -2 }} /> Vendas ainda não abertas</h2>
                  <p className="sub">{sale.reason} Volte em breve!</p>
                  {access.is_admin && <Link href="/admin/temporadas" className="btn outline sm">Configurar temporada</Link>}
                </>
              )}
            </>
          )}

          {orders && orders.length > 0 && (
            <>
              <hr className="divider" />
              <div className="eyebrow">Seus pedidos</div>
              {orders.map((order) => (
                <div key={order.id} className="spread small">
                  <span>{formatDateTime(order.created_at)} · {formatMoney(order.amount_cents, order.currency)}</span>
                  <span className={`pill ${order.status === 'approved' ? 'ok' : order.status === 'pending' ? 'gold' : 'muted'}`}>{ORDER_STATUS[order.status] ?? order.status}</span>
                </div>
              ))}
            </>
          )}
        </section>
      </div>
    </>
  );
}
