'use client';

import { useMemo, useState } from 'react';
import { useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { useAdminAction } from '@/components/admin';
import { useDialog } from '@/components/dialogs';
import { Loading, PageHead } from '@/components/ui';
import { formatDateTime, formatMoney, normalizeText } from '@/lib/format';
import type { Membership, Profile } from '@/lib/types';

const TABLES = ['memberships', 'profiles', 'admin_audit_logs', 'admin_usage_stats'] as const;
const SOURCE: Record<string, string> = { purchase: 'compra', courtesy: 'cortesia', admin: 'administração' };

export default function AdminAccess() {
  const { store, user } = useSession();
  const act = useAdminAction();
  const { confirm, ask } = useDialog();
  const { rows: profiles } = useTable('profiles', { order: [['created_at', 'desc']] });
  const { rows: memberships } = useTable('memberships');
  const { rows: seasons } = useTable('seasons', { order: [['created_at', 'desc']], limit: 1 });
  const { rows: orders } = useTable('orders', { order: [['created_at', 'desc']], limit: 30 });
  const { rows: transactions } = useTable('payment_transactions', { order: [['created_at', 'desc']], limit: 30 });
  const [q, setQ] = useState('');
  const season = seasons?.[0];

  const people = useMemo(() => {
    const term = normalizeText(q);
    return (profiles ?? []).filter((p) => !term || normalizeText(`${p.full_name} ${p.email ?? ''}`).includes(term));
  }, [profiles, q]);

  if (!profiles || !memberships) return <Loading />;
  const membershipOf = (profile: Profile) => memberships.find((m) => m.user_id === profile.id && m.season_id === season?.id);
  const emailOf = (id: string) => profiles.find((p) => p.id === id)?.email ?? id.slice(0, 8);

  async function grant(profile: Profile, current: Membership | undefined) {
    if (!season) return;
    await act(
      () =>
        current
          ? store.update('memberships', { id: current.id }, { status: 'active', revoked_at: null, revoke_reason: null, admin_locked: false })
          : store.insert('memberships', { user_id: profile.id, season_id: season.id, source: 'courtesy' }),
      { tables: [...TABLES], success: `Acesso liberado para ${profile.email ?? profile.full_name}` },
    );
  }
  async function revoke(profile: Profile, current: Membership) {
    const reason = await ask({ title: 'Revogar acesso', message: `${profile.email ?? profile.full_name} perde o acesso à temporada. O bloqueio manual impede que um pagamento antigo o reative.`, label: 'Motivo (fica registrado na auditoria)', defaultValue: 'Revogado pela administração', confirmLabel: 'Revogar', danger: true });
    if (reason === null) return;
    await act(
      () => store.update('memberships', { id: current.id }, { status: 'revoked', revoked_at: new Date().toISOString(), revoke_reason: reason.trim() || 'Revogado pela administração', admin_locked: true }),
      { tables: [...TABLES], success: `Acesso revogado de ${profile.email ?? profile.full_name}` },
    );
  }
  async function setRole(profile: Profile, role: 'customer' | 'admin') {
    const sure = await confirm(
      role === 'admin'
        ? { title: 'Tornar administrador(a)?', message: `${profile.email} poderá publicar receitas, confirmar permissões e gerenciar acessos.`, confirmLabel: 'Tornar admin' }
        : { title: 'Remover administração?', message: `${profile.email} volta a ser uma conta de cliente.`, confirmLabel: 'Remover', danger: true },
    );
    if (!sure) return;
    await act(() => store.rpc('admin_set_role', { p_user: profile.id, p_role: role }), { tables: [...TABLES], success: 'Papel atualizado' });
  }

  return (
    <>
      <PageHead eyebrow="Compradores" title="Pessoas e pagamentos." sub={`Acessos da temporada${season ? ` ${season.name}` : ''}, cortesias, papéis e histórico de pedidos.`} />
      <div className="toolbar"><input className="field" type="search" placeholder="Buscar por nome ou e-mail…" aria-label="Buscar pessoa" value={q} onChange={(e) => setQ(e.target.value)} /></div>
      <div className="tablewrap">
        <table className="table">
          <thead><tr><th>Pessoa</th><th>Papel</th><th>Acesso</th><th>Origem</th><th>Ações</th></tr></thead>
          <tbody>
            {people.map((profile) => {
              const current = membershipOf(profile);
              const active = current?.status === 'active';
              return (
                <tr key={profile.id}>
                  <td><span className="strong">{profile.full_name || '—'}</span><br /><span className="muted small">{profile.email}</span></td>
                  <td>{profile.role === 'admin' ? <span className="pill dark">Admin</span> : 'Cliente'}</td>
                  <td>
                    {active ? <span className="pill ok">Liberado</span> : current ? <span className="pill danger">Revogado</span> : <span className="pill muted">Sem acesso</span>}
                    {current?.admin_locked && <span className="pill warn" style={{ marginLeft: 6 }}>bloqueio manual</span>}
                  </td>
                  <td className="muted">{current ? SOURCE[current.source] : '—'}{current?.revoke_reason ? ` · ${current.revoke_reason}` : ''}</td>
                  <td>
                    <div className="row">
                      {active && current ? (
                        <button type="button" className="btn danger sm" onClick={() => revoke(profile, current)}>Revogar</button>
                      ) : (
                        <button type="button" className="btn outline sm" disabled={!season} onClick={() => grant(profile, current)}>Conceder cortesia</button>
                      )}
                      {profile.role === 'admin' ? (
                        profile.id !== user?.id && <button type="button" className="btn outline sm" onClick={() => setRole(profile, 'customer')}>Remover admin</button>
                      ) : (
                        <button type="button" className="btn outline sm" onClick={() => setRole(profile, 'admin')}>Tornar admin</button>
                      )}
                    </div>
                  </td>
                </tr>
              );
            })}
            {!people.length && <tr><td colSpan={5} className="muted center">Ninguém encontrado.</td></tr>}
          </tbody>
        </table>
      </div>

      <div className="sectionhead"><div><div className="eyebrow">Mercado Pago</div><h2>Pedidos recentes</h2></div></div>
      <div className="tablewrap">
        <table className="table">
          <thead><tr><th>Data</th><th>Pessoa</th><th>Valor</th><th>Situação</th><th>Pagamento</th></tr></thead>
          <tbody>
            {(orders ?? []).map((order) => (
              <tr key={order.id}>
                <td>{formatDateTime(order.created_at)}</td>
                <td>{emailOf(order.user_id)}</td>
                <td>{formatMoney(order.amount_cents, order.currency)}</td>
                <td><span className={`pill ${order.status === 'approved' ? 'ok' : order.status === 'pending' ? 'gold' : order.status === 'review_required' ? 'danger' : 'muted'}`}>{order.status}</span></td>
                <td className="muted">{order.provider_payment_id ?? '—'}</td>
              </tr>
            ))}
            {!orders?.length && <tr><td colSpan={5} className="muted center">Nenhum pedido ainda.</td></tr>}
          </tbody>
        </table>
      </div>

      <div className="sectionhead"><div><div className="eyebrow">Webhook</div><h2>Eventos de pagamento</h2><p className="sub">Cada aviso do Mercado Pago é registrado uma única vez; repetições só aumentam o contador.</p></div></div>
      <div className="tablewrap">
        <table className="table">
          <thead><tr><th>Último aviso</th><th>Pagamento</th><th>Situação</th><th>Detalhe</th><th>Valor</th><th>Avisos</th></tr></thead>
          <tbody>
            {(transactions ?? []).map((tx) => (
              <tr key={tx.id}>
                <td>{formatDateTime(tx.last_seen_at)}</td>
                <td>{tx.provider_payment_id}</td>
                <td>{tx.status}</td>
                <td className="muted">{tx.status_detail ?? '—'}</td>
                <td>{tx.amount_cents != null ? formatMoney(tx.amount_cents, tx.currency ?? 'BRL') : '—'}</td>
                <td>{tx.seen_count}</td>
              </tr>
            ))}
            {!transactions?.length && <tr><td colSpan={6} className="muted center">Nenhum evento recebido.</td></tr>}
          </tbody>
        </table>
      </div>
    </>
  );
}
