import { NextResponse } from 'next/server';
import { APP_MODE } from '@/lib/env';
import { paymentConfig } from '@/server/payments';
import { createSupabaseServerClient } from '@/server/supabase';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

/** Situação das integrações para o painel administrativo. Só informa "configurado ou não" — nunca valores. */
export async function GET() {
  if (APP_MODE === 'supabase') {
    const supabase = await createSupabaseServerClient();
    const { data: access } = await supabase.rpc('my_access');
    if (!access?.is_admin) return NextResponse.json({ error: 'forbidden' }, { status: 403 });
  } else if (APP_MODE !== 'demo') {
    return NextResponse.json({ error: 'not_found' }, { status: 404 });
  }
  const payments = paymentConfig();
  return NextResponse.json({
    mode: APP_MODE,
    supabase: APP_MODE === 'supabase',
    serviceRole: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.SUPABASE_SECRET_KEY),
    openai: Boolean(process.env.OPENAI_API_KEY),
    openaiModel: process.env.OPENAI_MODEL || 'gpt-6-luna',
    mercadoPagoToken: Boolean(payments.accessToken),
    mercadoPagoWebhookSecret: Boolean(payments.webhookSecret),
    paymentsEnabled: payments.enabled,
    paymentsReason: payments.reason,
    siteUrl: Boolean(process.env.NEXT_PUBLIC_SITE_URL),
  });
}
