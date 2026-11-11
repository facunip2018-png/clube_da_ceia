import { NextResponse } from 'next/server';
import { APP_MODE } from '@/lib/env';
import { createSupabaseServerClient, safeNext } from '@/server/supabase';

/** Retorno dos links enviados por e-mail (confirmação de cadastro e recuperação de senha). */
export async function GET(request: Request) {
  const url = new URL(request.url);
  const next = safeNext(url.searchParams.get('next'));
  if (APP_MODE !== 'supabase') return NextResponse.redirect(new URL('/', url.origin));
  const code = url.searchParams.get('code');
  if (code) {
    const supabase = await createSupabaseServerClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) return NextResponse.redirect(new URL(next, url.origin));
  }
  return NextResponse.redirect(new URL('/entrar?erro=link', url.origin));
}
