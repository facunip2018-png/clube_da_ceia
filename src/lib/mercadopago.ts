/**
 * Mercado Pago — validação da assinatura do webhook e utilidades de valor.
 * Módulo de servidor (usa node:crypto). Nunca importar em componentes de cliente.
 *
 * Assinatura: cabeçalho  x-signature: "ts=<ts>,v1=<hmac>"
 * Manifesto:  "id:<data.id>;request-id:<x-request-id>;ts:<ts>;"
 * HMAC-SHA256 (hex) do manifesto com a "assinatura secreta" gerada no painel de Webhooks.
 * Partes ausentes na notificação são removidas do manifesto; data.id alfanumérico vai em minúsculas.
 */
import { createHmac, timingSafeEqual } from 'node:crypto';

export interface ParsedSignature {
  ts: string;
  v1: string;
}

export function parseSignatureHeader(header: string | null | undefined): ParsedSignature | null {
  if (!header) return null;
  const parts = new Map<string, string>();
  for (const piece of header.split(',')) {
    const index = piece.indexOf('=');
    if (index > 0) parts.set(piece.slice(0, index).trim(), piece.slice(index + 1).trim());
  }
  const ts = parts.get('ts');
  const v1 = parts.get('v1');
  if (!ts || !v1 || !/^\d+$/.test(ts) || !/^[a-f0-9]{64}$/i.test(v1)) return null;
  return { ts, v1: v1.toLowerCase() };
}

export function buildManifest({ dataId, requestId, ts }: { dataId?: string | null; requestId?: string | null; ts: string }): string {
  let manifest = '';
  if (dataId) manifest += `id:${dataId.toLowerCase()};`;
  if (requestId) manifest += `request-id:${requestId};`;
  manifest += `ts:${ts};`;
  return manifest;
}

export function signManifest(manifest: string, secret: string): string {
  return createHmac('sha256', secret).update(manifest).digest('hex');
}

export function verifyWebhookSignature(input: {
  signatureHeader: string | null | undefined;
  requestId: string | null | undefined;
  dataId: string | null | undefined;
  secret: string | null | undefined;
}): boolean {
  if (!input.secret) return false;
  const parsed = parseSignatureHeader(input.signatureHeader);
  if (!parsed) return false;
  const expected = signManifest(buildManifest({ dataId: input.dataId, requestId: input.requestId, ts: parsed.ts }), input.secret);
  const a = Buffer.from(expected, 'hex');
  const b = Buffer.from(parsed.v1, 'hex');
  return a.length === b.length && timingSafeEqual(a, b);
}

/** Valor em reais (como a API devolve) → centavos inteiros. */
export const centsFromAmount = (amount: number) => Math.round(amount * 100);
export const amountFromCents = (cents: number) => Math.round(cents) / 100;
