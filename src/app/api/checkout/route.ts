import { NextResponse } from 'next/server';
import { APP_MODE } from '@/lib/env';
import { saleAvailability } from '@/lib/season';
import { amountFromCents } from '@/lib/mercadopago';
import { MP_API, paymentConfig } from '@/server/payments';
import { createSupabaseAdminClient, createSupabaseServerClient } from '@/server/supabase';
import type { Season } from '@/lib/types';

export const runtime = 'nodejs';

const fail = (status: number, code: string, message: string) => NextResponse.json({ error: code, message }, { status });

/**
 * Inicia a compra da temporada no Checkout Pro:
 *   1. cria o pedido (orders) com o preço lido do banco — nunca do navegador;
 *   2. cria a preferência no Mercado Pago com external_reference = id do pedido;
 *   3. devolve o endereço do checkout.
 * O acesso NÃO é liberado aqui: só o webhook, depois de consultar o pagamento na API.
 */
export async function POST(request: Request) {
  if (APP_MODE !== 'supabase') return fail(404, 'not_found', 'Indisponível neste modo.');
  const config = paymentConfig();
  if (!config.enabled || !config.accessToken) return fail(503, 'payments_disabled', 'As compras ainda não estão habilitadas. Tente novamente em breve.');

  const supabase = await createSupabaseServerClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) return fail(401, 'not_authenticated', 'Entre na sua conta para comprar.');

  const admin = createSupabaseAdminClient();
  if (!admin) return fail(503, 'payments_disabled', 'As compras ainda não estão habilitadas.');

  const { data: season } = await admin.from('seasons').select('*').eq('status', 'active').order('created_at', { ascending: false }).limit(1).maybeSingle<Season>();
  const sale = saleAvailability(season);
  if (!season || !sale.open || !season.price_cents) return fail(409, 'sales_closed', sale.reason ?? 'Vendas indisponíveis.');

  const { data: membership } = await admin.from('memberships').select('status, admin_locked').eq('user_id', auth.user.id).eq('season_id', season.id).maybeSingle();
  if (membership?.status === 'active') return fail(409, 'already_member', 'Você já tem o acesso desta temporada.');
  // acesso bloqueado manualmente: não deixa pagar por algo que não será liberado
  if (membership?.admin_locked) return fail(403, 'access_locked', 'Seu acesso a esta temporada foi suspenso pela administração. Fale com o suporte do Clube.');

  const { data: order, error: orderError } = await admin
    .from('orders')
    .insert({ user_id: auth.user.id, season_id: season.id, amount_cents: season.price_cents, currency: season.currency })
    .select('id')
    .single();
  if (orderError || !order) return fail(500, 'order_failed', 'Não foi possível criar o pedido.');

  const origin = (process.env.NEXT_PUBLIC_SITE_URL || new URL(request.url).origin).replace(/\/$/, '');
  const preference = {
    items: [
      {
        id: season.slug,
        title: `Clube da Ceia Perfeita — ${season.name}`,
        description: 'Acesso à temporada (pagamento único)',
        quantity: 1,
        currency_id: season.currency,
        unit_price: amountFromCents(season.price_cents),
      },
    ],
    payer: { email: auth.user.email },
    external_reference: order.id,
    metadata: { order_id: order.id, season_id: season.id },
    back_urls: {
      success: `${origin}/acesso/retorno?status=success`,
      pending: `${origin}/acesso/retorno?status=pending`,
      failure: `${origin}/acesso/retorno?status=failure`,
    },
    auto_return: 'approved',
    statement_descriptor: 'CEIA PERFEITA',
    // a URL de notificação é a configurada no painel do Mercado Pago (Webhooks), que gera a assinatura secreta
  };

  let created: { id?: string; init_point?: string; sandbox_init_point?: string } | null = null;
  try {
    const response = await fetch(`${MP_API}/checkout/preferences`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${config.accessToken}`, 'Content-Type': 'application/json', 'X-Idempotency-Key': order.id },
      body: JSON.stringify(preference),
      signal: AbortSignal.timeout(15_000),
    });
    if (response.ok) created = await response.json();
    else console.error('[checkout] Mercado Pago respondeu', response.status);
  } catch (error) {
    console.error('[checkout] falha ao criar preferência:', (error as Error).message);
  }
  if (!created?.id || !created.init_point) {
    await admin.from('orders').update({ status: 'cancelled' }).eq('id', order.id);
    return fail(502, 'preference_failed', 'O Mercado Pago não respondeu. Tente novamente em instantes.');
  }

  await admin.from('orders').update({ provider_preference_id: created.id }).eq('id', order.id);
  const sandbox = config.accessToken.startsWith('TEST-');
  return NextResponse.json({ order_id: order.id, init_point: sandbox ? created.sandbox_init_point ?? created.init_point : created.init_point });
}
