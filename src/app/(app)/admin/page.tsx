'use client';

import Link from 'next/link';
import useSWR from 'swr';
import { Check, X } from 'lucide-react';
import { useRpc, useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { Loading, Notice, PageHead } from '@/components/ui';
import { formatMoney } from '@/lib/format';

interface Health {
  mode: string; supabase: boolean; serviceRole: boolean; openai: boolean; openaiModel: string; mercadoPagoToken: boolean;
  mercadoPagoWebhookSecret: boolean; paymentsEnabled: boolean; paymentsReason: string | null; siteUrl: boolean;
}

function Mark({ ok }: { ok: boolean }) {
  return <span className="mark">{ok ? <Check /> : <X />}</span>;
}

export default function AdminHome() {
  const { mode } = useSession();
  const { rows: recipes } = useTable('recipes');
  const { rows: documents } = useTable('source_documents');
  const { rows: flags } = useTable('review_flags', { eq: { resolved_at: null } });
  const { rows: seasons } = useTable('seasons', { order: [['created_at', 'desc']], limit: 1 });
  const { data: usage } = useRpc('admin_usage_stats');
  const { data: health } = useSWR<Health>('/api/health', (url: string) => fetch(url).then((r) => r.json()), { revalidateOnFocus: false });

  if (!recipes || !documents || !flags) return <Loading />;
  const structured = recipes.filter((r) => r.content_state === 'structured');
  const published = recipes.filter((r) => r.status === 'published');
  const received = documents.filter((d) => d.file_status === 'received' || d.file_status === 'stored');
  const confirmed = documents.filter((d) => d.commercial_permission === 'confirmed');
  const openFlags = flags.filter((f) => f.severity !== 'info');
  const season = seasons?.[0];
  const seasonReady = Boolean(season && season.status === 'active' && season.price_cents);
  const stats = (usage ?? {}) as Record<string, number> & { top_favorites?: { title: string; total: number }[] };

  const steps = [
    { ok: received.length === documents.length, title: 'Receber os PDFs de origem', detail: `${received.length} de ${documents.length} documentos recebidos.`, href: '/admin/documentos' },
    { ok: structured.length > 0 && openFlags.length === 0, title: 'Revisar as fichas estruturadas', detail: `${structured.length} ficha(s) estruturada(s) · ${openFlags.length} ponto(s) de revisão em aberto.`, href: '/admin/receitas' },
    { ok: confirmed.length > 0, title: 'Confirmar a permissão comercial de cada material', detail: `${confirmed.length} de ${documents.length} documentos com permissão confirmada.`, href: '/admin/documentos' },
    { ok: published.length > 0, title: 'Publicar as receitas aprovadas', detail: `${published.length} de ${recipes.length} itens no ar.`, href: '/admin/receitas' },
    { ok: seasonReady, title: 'Definir preço e ativar a temporada', detail: season ? `${season.name}: ${season.status === 'active' ? 'ativa' : 'em rascunho'}${season.price_cents ? ` · ${formatMoney(season.price_cents)}` : ' · preço não definido'}.` : 'Nenhuma temporada.', href: '/admin/temporadas' },
    { ok: Boolean(health?.paymentsEnabled), title: 'Habilitar os pagamentos (Mercado Pago)', detail: health?.paymentsReason ?? 'Credenciais configuradas.', href: null },
    { ok: Boolean(health?.openai), title: 'Conectar o Chef IA (OpenAI)', detail: health?.openai ? `Modelo: ${health.openaiModel}.` : 'Sem chave: o Chef responde por consulta direta às fichas, sem IA generativa.', href: null },
  ];

  return (
    <>
      <PageHead eyebrow="Área restrita" title="Painel administrativo." sub="Curadoria do catálogo, temporada, acessos e pagamentos." />
      {mode === 'demo' && (
        <div style={{ marginBottom: 16 }}>
          <Notice>Este é o painel em <b>modo demonstração</b>: as alterações ficam só neste navegador. Em produção, a rota é protegida no servidor e os dados pelo RLS do Supabase.</Notice>
        </div>
      )}
      <div className="adminstats">
        <div className="adminstat"><span className="eyebrow">Itens no catálogo</span><strong>{recipes.length}</strong><span className="sub small">{structured.length} com ficha estruturada</span></div>
        <div className="adminstat"><span className="eyebrow">Publicadas</span><strong>{published.length}</strong><span className="sub small">visíveis para clientes</span></div>
        <div className="adminstat"><span className="eyebrow">Pontos de revisão</span><strong>{openFlags.length}</strong><span className="sub small">em aberto</span></div>
        <div className="adminstat"><span className="eyebrow">Documentos</span><strong>{received.length}/{documents.length}</strong><span className="sub small">PDFs recebidos</span></div>
      </div>

      <div className="twocol" style={{ marginTop: 18 }}>
        <section className="panel">
          <div className="eyebrow">Guia de publicação</div>
          <h2 style={{ margin: '6px 0 16px' }}>O que falta para abrir a temporada</h2>
          <ul className="checklist">
            {steps.map((step) => (
              <li key={step.title} className={step.ok ? 'ok' : ''}>
                <Mark ok={step.ok} />
                <div>
                  {step.href ? <Link href={step.href}><b>{step.title} →</b></Link> : <b>{step.title}</b>}
                  <small>{step.detail}</small>
                </div>
              </li>
            ))}
          </ul>
        </section>

        <section className="panel">
          <div className="eyebrow">Uso do app</div>
          <h2 style={{ margin: '6px 0 16px' }}>Estatísticas</h2>
          <div className="stack small">
            {[
              ['Pessoas cadastradas', stats.users],
              ['Acessos ativos', stats.active_memberships],
              ['Pedidos aprovados', stats.orders_approved],
              ['Receita confirmada', stats.revenue_cents != null ? formatMoney(stats.revenue_cents) : undefined],
              ['Planejamentos de ceia', stats.plans],
              ['Receitas concluídas no modo cozinheiro', stats.cooking_sessions_finished],
              ['Favoritas', stats.favorites],
              ['Perguntas ao Chef (7 dias)', stats.chef_messages_7d],
              ['Desafios concluídos', stats.challenges_completed],
            ].map(([label, value]) => (
              <div key={label as string} className="spread" style={{ borderBottom: '1px solid #f0efe9', paddingBottom: 8 }}>
                <span className="muted">{label}</span><b>{value ?? '–'}</b>
              </div>
            ))}
            {stats.top_favorites && stats.top_favorites.length > 0 && (
              <p className="muted">Mais favoritadas: {stats.top_favorites.map((t) => `${t.title} (${t.total})`).join(' · ')}</p>
            )}
          </div>
        </section>
      </div>

      <section className="panel" style={{ marginTop: 18 }}>
        <div className="eyebrow">Integrações</div>
        <h2 style={{ margin: '6px 0 16px' }}>Situação das conexões</h2>
        {health ? (
          <ul className="checklist">
            <li className={health.supabase ? 'ok' : ''}><Mark ok={health.supabase} /><div><b>Supabase (banco, login e arquivos)</b><small>{health.supabase ? 'Conectado.' : 'Não conectado — app em modo demonstração.'}</small></div></li>
            <li className={health.serviceRole ? 'ok' : ''}><Mark ok={health.serviceRole} /><div><b>Chave de serviço do Supabase (somente servidor)</b><small>Necessária para o checkout e o webhook de pagamentos.</small></div></li>
            <li className={health.openai ? 'ok' : ''}><Mark ok={health.openai} /><div><b>OpenAI (Chef IA)</b><small>{health.openai ? `Chave configurada no servidor · modelo ${health.openaiModel}.` : 'Sem chave configurada.'}</small></div></li>
            <li className={health.mercadoPagoToken && health.mercadoPagoWebhookSecret ? 'ok' : ''}><Mark ok={health.mercadoPagoToken && health.mercadoPagoWebhookSecret} /><div><b>Mercado Pago (Access Token e assinatura do webhook)</b><small>{health.paymentsEnabled ? 'Pagamentos habilitados.' : health.paymentsReason}</small></div></li>
          </ul>
        ) : (
          <div className="skeleton" style={{ height: 120 }} />
        )}
        <p className="muted small" style={{ marginTop: 12 }}>As chaves nunca aparecem aqui nem chegam ao navegador — este painel mostra apenas se cada uma está configurada.</p>
      </section>
    </>
  );
}
