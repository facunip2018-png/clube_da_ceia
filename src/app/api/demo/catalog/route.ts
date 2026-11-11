import { createHash } from 'node:crypto';
import { NextResponse } from 'next/server';
import { APP_MODE } from '@/lib/env';
import demo from '@/server/demo-data.generated.json';

/**
 * Catálogo do MODO DEMONSTRAÇÃO. Fora dele esta rota não existe (404):
 * em produção o conteúdo vem do Supabase, protegido por RLS.
 */
const body = APP_MODE === 'demo' ? { version: createHash('sha1').update(JSON.stringify(demo)).digest('hex').slice(0, 12), tables: demo.tables } : null;

export function GET() {
  if (!body) return NextResponse.json({ error: 'not_found' }, { status: 404 });
  return NextResponse.json(body, { headers: { 'Cache-Control': 'no-store' } });
}
