import type { EmailOtpType } from '@supabase/supabase-js';
import { NextResponse } from 'next/server';
import { APP_MODE } from '@/lib/env';
import { createSupabaseServerClient, safeNext } from '@/server/supabase';

/** Alternativa para modelos de e-mail que usam token_hash ({{ .TokenHash }}). */
export async function GET(request: Request) {
  const url = new URL(request.url);
  const next = safeNext(url.searchParams.get('next'));
  if (APP_MODE !== 'supabase') return NextResponse.redirect(new URL('/', url.origin));
  const tokenHash = url.searchParams.get('token_hash');
  const type = url.searchParams.get('type') as EmailOtpType | null;
  if (tokenHash && type) {
    const supabase = await createSupabaseServerClient();
    const { error } = await supabase.auth.verifyOtp({ type, token_hash: tokenHash });
    if (!error) return NextResponse.redirect(new URL(type === 'recovery' ? '/redefinir-senha' : next, url.origin));
  }
  return NextResponse.redirect(new URL('/entrar?erro=link', url.origin));
}
