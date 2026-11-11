import { NextResponse } from 'next/server';
import { centsFromAmount, verifyWebhookSignature } from '@/lib/mercadopago';
import { MP_API, paymentConfig } from '@/server/payments';
import { createSupabaseAdminClient, isUuid } from '@/server/supabase';

export const runtime = 'nodejs';

/**
 * Webhook do Mercado Pago (tópico "payment").
 *   1. valida a assinatura (x-signature) com a assinatura secreta do painel;
 *   2. NÃO confia no corpo: busca o pagamento na API do Mercado Pago;
 *   3. entrega o resultado à função process_payment_event(), que confere valor/moeda,
 *      é idempotente (o mesmo aviso pode chegar várias vezes) e só então libera ou revoga o acesso.
 * Responde 200 rapidamente; erros temporários devolvem 500 para o Mercado Pago tentar de novo.
 */
export async function POST(request: Request) {
  const config = paymentConfig();
  if (!config.webhookSecret || !config.accessToken) return NextResponse.json({ error: 'not_configured' }, { status: 503 });

  const url = new URL(request.url);
  const body = (await request.json().catch(() => null)) as { type?: string; action?: string; data?: { id?: string | number } } | null;
  const dataId = url.searchParams.get('data.id') ?? (body?.data?.id != null ? String(body.data.id) : null);
  const topic = url.searchParams.get('type') ?? body?.type ?? url.searchParams.get('topic');

  const valid = verifyWebhookSignature({
    signatureHeader: request.headers.get('x-signature'),
    requestId: request.headers.get('x-request-id'),
    dataId,
    secret: config.webhookSecret,
  });
  if (!valid) return NextResponse.json({ error: 'invalid_signature' }, { status: 401 });

  if (topic !== 'payment' || !dataId || !/^\d+$/.test(dataId)) return NextResponse.json({ received: true, ignored: 'topic' });

  let payment: {
    id: number; status: string; status_detail?: string; transaction_amount?: number; currency_id?: string; external_reference?: string | null;
    date_approved?: string | null; payment_method_id?: string; payment_type_id?: string;
  };
  try {
    const response = await fetch(`${MP_API}/v1/payments/${dataId}`, {
      headers: { Authorization: `Bearer ${config.accessToken}` },
      cache: 'no-store',
      signal: AbortSignal.timeout(12_000),
    });
    if (response.status === 404) return NextResponse.json({ received: true, ignored: 'payment_not_found' });
    if (!response.ok) return NextResponse.json({ error: 'payment_lookup_failed' }, { status: 500 });
    payment = await response.json();
  } catch {
    return NextResponse.json({ error: 'payment_lookup_failed' }, { status: 500 });
  }

  // pagamentos que não nasceram neste app (sem o id do pedido) são ignorados
  if (!isUuid(payment.external_reference)) return NextResponse.json({ received: true, ignored: 'external_reference' });

  const admin = createSupabaseAdminClient();
  if (!admin) return NextResponse.json({ error: 'not_configured' }, { status: 503 });

  const { data, error } = await admin.rpc('process_payment_event', {
    p_order_id: payment.external_reference,
    p_provider_payment_id: String(payment.id),
    p_status: payment.status,
    p_status_detail: payment.status_detail ?? null,
    p_amount_cents: payment.transaction_amount != null ? centsFromAmount(payment.transaction_amount) : null,
    p_currency: payment.currency_id ?? null,
    p_raw: {
      id: payment.id, status: payment.status, status_detail: payment.status_detail ?? null, date_approved: payment.date_approved ?? null,
      payment_method_id: payment.payment_method_id ?? null, payment_type_id: payment.payment_type_id ?? null, action: body?.action ?? null,
    },
  });
  if (error) {
    console.error('[webhook] process_payment_event falhou:', error.message);
    return NextResponse.json({ error: 'processing_failed' }, { status: 500 });
  }
  return NextResponse.json({ received: true, result: data });
}
