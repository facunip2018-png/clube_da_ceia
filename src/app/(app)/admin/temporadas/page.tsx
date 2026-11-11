'use client';

import { useState, type FormEvent } from 'react';
import { Save } from 'lucide-react';
import { useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { fromLocalInput, toLocalInput, useAdminAction } from '@/components/admin';
import { Loading, Notice, PageHead } from '@/components/ui';
import { saleAvailability } from '@/lib/season';
import { formatMoney } from '@/lib/format';
import type { Season } from '@/lib/types';

function SeasonForm({ season }: { season: Season }) {
  const { store, refresh } = useSession();
  const act = useAdminAction();
  const [form, setForm] = useState({
    name: season.name,
    description: season.description ?? '',
    status: season.status,
    price: season.price_cents != null ? (season.price_cents / 100).toFixed(2).replace('.', ',') : '',
    sales_starts_at: toLocalInput(season.sales_starts_at),
    sales_ends_at: toLocalInput(season.sales_ends_at),
    access_starts_at: toLocalInput(season.access_starts_at),
    access_ends_at: toLocalInput(season.access_ends_at),
  });
  const set = (key: keyof typeof form) => (event: { target: { value: string } }) => setForm((f) => ({ ...f, [key]: event.target.value }));
  const sale = saleAvailability(season);

  async function save(event: FormEvent) {
    event.preventDefault();
    const price = form.price.trim() ? Math.round(Number(form.price.replace(/\./g, '').replace(',', '.')) * 100) : null;
    const ok = await act(
      async () => {
        if (price != null && (!Number.isFinite(price) || price <= 0)) throw new Error('Informe um preço válido (ex.: 49,90).');
        if (form.status === 'active' && (!form.access_starts_at || !form.access_ends_at)) throw new Error('Defina o período de acesso antes de ativar a temporada.');
        if (form.access_starts_at && form.access_ends_at && form.access_ends_at <= form.access_starts_at) throw new Error('O fim do acesso precisa ser depois do início.');
        await store.update('seasons', { id: season.id }, {
          name: form.name.trim() || season.name,
          description: form.description.trim() || null,
          status: form.status,
          price_cents: price,
          sales_starts_at: fromLocalInput(form.sales_starts_at),
          sales_ends_at: fromLocalInput(form.sales_ends_at),
          access_starts_at: fromLocalInput(form.access_starts_at),
          access_ends_at: fromLocalInput(form.access_ends_at),
        });
      },
      { tables: ['seasons', 'admin_audit_logs', 'my_access'], success: 'Temporada salva' },
    );
    if (ok) await refresh();
  }

  return (
    <section className="panel">
      <div className="spread" style={{ flexWrap: 'wrap' }}>
        <div>
          <div className="eyebrow">Temporada</div>
          <h2 style={{ margin: '6px 0' }}>{season.name}</h2>
        </div>
        <div className="row">
          <span className={`pill ${season.status === 'active' ? 'ok' : 'muted'}`}>{season.status === 'active' ? 'Ativa' : season.status === 'draft' ? 'Rascunho' : 'Arquivada'}</span>
          <span className={`pill ${sale.open ? 'ok' : 'warn'}`}>{sale.open ? `À venda por ${formatMoney(season.price_cents ?? 0)}` : 'Vendas fechadas'}</span>
        </div>
      </div>
      {season.admin_notice && <div style={{ margin: '12px 0' }}><Notice>{season.admin_notice}</Notice></div>}
      {!sale.open && <p className="muted small" style={{ marginBottom: 12 }}>Motivo: {sale.reason}</p>}
      <form className="formgrid" onSubmit={save}>
        <div className="group"><label htmlFor="s-name">Nome</label><input id="s-name" className="field" value={form.name} onChange={set('name')} required /></div>
        <div className="group">
          <label htmlFor="s-status">Situação</label>
          <select id="s-status" className="select" value={form.status} onChange={set('status')}>
            <option value="draft">Rascunho (sem vendas e sem acesso)</option>
            <option value="active">Ativa</option>
            <option value="archived">Arquivada</option>
          </select>
        </div>
        <div className="group full"><label htmlFor="s-desc">Descrição</label><input id="s-desc" className="field" value={form.description} onChange={set('description')} /></div>
        <div className="group"><label htmlFor="s-price">Preço (R$) — pagamento único</label><input id="s-price" className="field" inputMode="decimal" placeholder="Ex.: 49,90" value={form.price} onChange={set('price')} /></div>
        <div />
        <div className="group"><label htmlFor="s-ss">Início das vendas</label><input id="s-ss" className="field" type="datetime-local" value={form.sales_starts_at} onChange={set('sales_starts_at')} /></div>
        <div className="group"><label htmlFor="s-se">Fim das vendas</label><input id="s-se" className="field" type="datetime-local" value={form.sales_ends_at} onChange={set('sales_ends_at')} /></div>
        <div className="group"><label htmlFor="s-as">Início do acesso</label><input id="s-as" className="field" type="datetime-local" value={form.access_starts_at} onChange={set('access_starts_at')} /></div>
        <div className="group"><label htmlFor="s-ae">Fim do acesso</label><input id="s-ae" className="field" type="datetime-local" value={form.access_ends_at} onChange={set('access_ends_at')} /></div>
        <p className="muted small full">Datas no fuso deste aparelho. O acesso das clientes vale somente dentro do período de acesso e com a temporada ativa. Mudanças de preço valem para novos pedidos.</p>
        <div className="group full"><button type="submit" className="btn dark"><Save /> Salvar temporada</button></div>
      </form>
    </section>
  );
}

export default function AdminSeasons() {
  const { rows: seasons } = useTable('seasons', { order: [['created_at', 'desc']] });
  if (!seasons) return <Loading />;
  return (
    <>
      <PageHead eyebrow="Venda sazonal" title="Temporada." sub="Defina preço, período de vendas e período de acesso. O pagamento é único por temporada." />
      <div className="stack">{seasons.map((season) => <SeasonForm key={`${season.id}:${season.updated_at}`} season={season} />)}</div>
    </>
  );
}
