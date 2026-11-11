/** Configuração de pagamentos (somente servidor). */
export interface PaymentConfig {
  enabled: boolean;
  accessToken: string | null;
  webhookSecret: string | null;
  /** motivo, em linguagem simples, de os pagamentos estarem desligados */
  reason: string | null;
}

export function paymentConfig(): PaymentConfig {
  const accessToken = process.env.MERCADOPAGO_ACCESS_TOKEN || null;
  const webhookSecret = process.env.MERCADOPAGO_WEBHOOK_SECRET || null;
  const flag = process.env.PAYMENTS_ENABLED === 'true';
  const serviceRole = Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.SUPABASE_SECRET_KEY);
  const reason = !flag
    ? 'Pagamentos ainda não foram habilitados (PAYMENTS_ENABLED).'
    : !accessToken
      ? 'Falta o Access Token do Mercado Pago.'
      : !webhookSecret
        ? 'Falta a assinatura secreta do webhook do Mercado Pago.'
        : !serviceRole
          ? 'Falta a chave de serviço do Supabase no servidor.'
          : null;
  return { enabled: reason === null, accessToken, webhookSecret, reason };
}

export const MP_API = 'https://api.mercadopago.com';
