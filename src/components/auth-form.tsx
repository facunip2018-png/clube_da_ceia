'use client';

import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { useState, type FormEvent } from 'react';
import { useSession } from '@/data/session';
import { Notice } from './ui';

type Mode = 'login' | 'signup' | 'recover' | 'reset';

const COPY: Record<Mode, { title: string; sub: string; action: string }> = {
  login: { title: 'Entrar no Clube', sub: 'Use o e-mail e a senha da sua conta.', action: 'Entrar' },
  signup: { title: 'Criar minha conta', sub: 'Leva menos de um minuto.', action: 'Criar conta' },
  recover: { title: 'Recuperar senha', sub: 'Enviaremos um link para você criar uma nova senha.', action: 'Enviar link' },
  reset: { title: 'Nova senha', sub: 'Escolha uma senha com pelo menos 8 caracteres.', action: 'Salvar nova senha' },
};

/** Traduz as mensagens mais comuns do Supabase Auth. */
function friendly(message: string): string {
  if (/invalid login credentials/i.test(message)) return 'E-mail ou senha incorretos.';
  if (/email not confirmed/i.test(message)) return 'Confirme seu e-mail pelo link que enviamos antes de entrar.';
  if (/already registered|already been registered/i.test(message)) return 'Já existe uma conta com este e-mail. Tente entrar.';
  if (/password should be at least/i.test(message)) return 'A senha é muito curta.';
  if (/rate limit|too many/i.test(message)) return 'Muitas tentativas. Aguarde alguns minutos e tente de novo.';
  if (/session missing|not authenticated/i.test(message)) return 'O link expirou. Peça um novo link de recuperação.';
  return 'Não foi possível concluir. Verifique os dados e tente novamente.';
}

const safeNext = (value: string | null) => (value && value.startsWith('/') && !value.startsWith('//') ? value : '/');

export function AuthForm({ mode }: { mode: Mode }) {
  const router = useRouter();
  const params = useSearchParams();
  const next = safeNext(params.get('next'));
  const { supabase, mode: appMode, user } = useSession();
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(params.get('erro') === 'link'
      ? 'Não foi possível abrir este link neste navegador. Se você estava confirmando o cadastro, a conta já pode estar ativa: tente entrar com e-mail e senha. Para redefinir a senha, peça um novo link.'
      : null);
  const [done, setDone] = useState<string | null>(null);
  const copy = COPY[mode];

  if (appMode !== 'supabase' || !supabase) {
    return (
      <>
        <h1>{copy.title}</h1>
        <Notice>No modo demonstração não há login: escolha um perfil na barra “Demonstração”, no topo do app.</Notice>
        <Link href="/" className="btn dark">Ir para o início</Link>
      </>
    );
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!supabase) return;
    setBusy(true);
    setError(null);
    try {
      const origin = window.location.origin;
      if (mode === 'login') {
        const { error: failure } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
        if (failure) throw failure;
        router.replace(next);
        router.refresh();
      } else if (mode === 'signup') {
        const { data, error: failure } = await supabase.auth.signUp({
          email: email.trim(),
          password,
          options: { data: { full_name: name.trim() }, emailRedirectTo: `${origin}/auth/callback?next=${encodeURIComponent(next)}` },
        });
        if (failure) throw failure;
        if (data.session) {
          router.replace(next);
          router.refresh();
        } else {
          setDone('Conta criada! Enviamos um link de confirmação para o seu e-mail. Abra-o para ativar o acesso.');
        }
      } else if (mode === 'recover') {
        const { error: failure } = await supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo: `${origin}/auth/callback?next=/redefinir-senha` });
        if (failure) throw failure;
        setDone('Se houver uma conta com este e-mail, você receberá um link para criar uma nova senha.');
      } else {
        const { error: failure } = await supabase.auth.updateUser({ password });
        if (failure) throw failure;
        setDone('Senha atualizada.');
        router.replace('/');
        router.refresh();
      }
    } catch (failure) {
      setError(friendly((failure as Error).message ?? ''));
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <div>
        <h1>{copy.title}</h1>
        <p className="sub" style={{ marginTop: 6 }}>{copy.sub}</p>
      </div>
      {error && <Notice tone="danger">{error}</Notice>}
      {done ? (
        <Notice tone="soft">{done}</Notice>
      ) : mode === 'reset' && !user ? (
        <Notice>Abra esta página pelo link de recuperação enviado ao seu e-mail. <Link href="/recuperar-senha"><b>Pedir um novo link</b></Link>.</Notice>
      ) : (
        <form className="stack" onSubmit={submit}>
          {mode === 'signup' && (
            <div className="group"><label htmlFor="a-name">Seu nome</label><input id="a-name" className="field" value={name} onChange={(e) => setName(e.target.value)} autoComplete="name" maxLength={80} required /></div>
          )}
          {mode !== 'reset' && (
            <div className="group"><label htmlFor="a-email">E-mail</label><input id="a-email" className="field" type="email" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="email" inputMode="email" required /></div>
          )}
          {mode !== 'recover' && (
            <div className="group">
              <label htmlFor="a-pass">{mode === 'reset' ? 'Nova senha' : 'Senha'}</label>
              <input id="a-pass" className="field" type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete={mode === 'login' ? 'current-password' : 'new-password'} minLength={mode === 'login' ? undefined : 8} required />
              {mode !== 'login' && <span className="hint">Mínimo de 8 caracteres.</span>}
            </div>
          )}
          <button type="submit" className="btn dark block" disabled={busy}>{busy ? 'Aguarde…' : copy.action}</button>
        </form>
      )}
      <div className="links">
        {mode === 'login' ? (
          <>
            <Link href={`/cadastro${next !== '/' ? `?next=${encodeURIComponent(next)}` : ''}`}>Criar conta</Link>
            <Link href="/recuperar-senha">Esqueci minha senha</Link>
          </>
        ) : (
          <Link href={`/entrar${next !== '/' ? `?next=${encodeURIComponent(next)}` : ''}`}>← Voltar para entrar</Link>
        )}
        <Link href="/">Conhecer o Clube</Link>
      </div>
    </>
  );
}
