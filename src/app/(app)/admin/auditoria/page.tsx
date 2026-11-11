'use client';

import { useTable } from '@/data/hooks';
import { Loading, PageHead } from '@/components/ui';
import { formatDateTime } from '@/lib/format';

export default function AdminAudit() {
  const { rows: logs } = useTable('admin_audit_logs', { order: [['created_at', 'desc']], limit: 150 });
  if (!logs) return <Loading />;
  return (
    <>
      <PageHead eyebrow="Rastreabilidade" title="Auditoria." sub="Registro das ações administrativas: publicações, permissões, acessos e papéis. Os registros são gravados pelo banco e não podem ser editados." />
      <div className="tablewrap">
        <table className="table">
          <thead><tr><th>Quando</th><th>Quem</th><th>Ação</th><th>Resumo</th></tr></thead>
          <tbody>
            {logs.map((log) => (
              <tr key={log.id}>
                <td style={{ whiteSpace: 'nowrap' }}>{formatDateTime(log.created_at)}</td>
                <td>{log.actor_email ?? 'sistema'}</td>
                <td><span className="pill muted">{log.action}</span></td>
                <td>{log.summary ?? '—'}</td>
              </tr>
            ))}
            {!logs.length && <tr><td colSpan={4} className="muted center">Nenhuma ação registrada ainda.</td></tr>}
          </tbody>
        </table>
      </div>
    </>
  );
}
