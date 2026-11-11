import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

/**
 * Proxy (antigo "middleware") — roda antes das páginas:
 *   • renova a sessão do Supabase nos cookies;
 *   • protege /admin no servidor: sem login → /entrar; sem papel de admin → início.
 * A proteção dos DADOS continua sendo o RLS do banco; isto evita apenas que a tela seja servida.
 */
export async function proxy(request: NextRequest) {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !key) return NextResponse.next();

  let response = NextResponse.next({ request });
  const supabase = createServerClient(url, key, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll: (list) => {
        list.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        list.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
      },
    },
  });

  const { data } = await supabase.auth.getUser();
  const { pathname } = request.nextUrl;

  if (pathname.startsWith('/admin')) {
    const redirect = (to: string) => {
      const target = request.nextUrl.clone();
      target.pathname = to;
      target.search = to === '/entrar' ? `?next=${encodeURIComponent(pathname)}` : '';
      const redirected = NextResponse.redirect(target);
      response.cookies.getAll().forEach((cookie) => redirected.cookies.set(cookie));
      return redirected;
    };
    if (!data.user) return redirect('/entrar');
    const { data: access } = await supabase.rpc('my_access');
    if (!access?.is_admin) return redirect('/');
  }
  return response;
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|icon.png|apple-icon.png|manifest.webmanifest|sw.js|icons/|images/|api/webhooks/|api/demo/).*)'],
};
