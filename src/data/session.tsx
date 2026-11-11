'use client';

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { createBrowserClient } from '@supabase/ssr';
import type { SupabaseClient } from '@supabase/supabase-js';
import { APP_MODE, SUPABASE_ANON_KEY, SUPABASE_URL, type AppMode } from '@/lib/env';
import type { Access } from '@/lib/types';
import { safeStorage } from '@/lib/safe-storage';
import { DEMO_USERS, LocalStore, type Persona } from './local-store';
import { SupabaseStore } from './supabase-store';
import type { DataStore } from './store';

export interface SessionUser {
  id: string;
  email: string | null;
  name: string;
}

interface SessionValue {
  mode: AppMode;
  /** true quando já sabemos quem é a pessoa e qual o acesso dela */
  ready: boolean;
  user: SessionUser | null;
  access: Access;
  store: DataStore;
  /** muda sempre que identidade ou acesso mudam (compõe as chaves de cache) */
  key: string;
  supabase: SupabaseClient | null;
  persona: Persona | null;
  setPersona: (persona: Persona) => void;
  refresh: () => Promise<void>;
  signOut: () => Promise<void>;
  resetDemo: () => void;
}

const NO_ACCESS: Access = { authenticated: false, is_admin: false, has_access: false };
const PERSONA_KEY = 'ccp.demo.persona';

let browserClient: SupabaseClient | null = null;
export function getSupabaseBrowserClient(): SupabaseClient | null {
  if (APP_MODE !== 'supabase') return null;
  browserClient ??= createBrowserClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  return browserClient;
}

async function fetchDemoCatalog() {
  const response = await fetch('/api/demo/catalog', { cache: 'no-store' });
  if (!response.ok) throw new Error('Não foi possível carregar o catálogo de demonstração.');
  return response.json();
}

const SessionContext = createContext<SessionValue | null>(null);

export function SessionProvider({ children }: { children: ReactNode }) {
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);
  const storeRef = useRef<DataStore | null>(null);
  if (!storeRef.current) {
    storeRef.current = supabase ? new SupabaseStore(supabase) : new LocalStore(fetchDemoCatalog);
  }
  const store = storeRef.current;

  const [ready, setReady] = useState(false);
  const [user, setUser] = useState<SessionUser | null>(null);
  const [access, setAccess] = useState<Access>(NO_ACCESS);
  const [persona, setPersonaState] = useState<Persona | null>(APP_MODE === 'demo' ? 'admin' : null);
  const [version, setVersion] = useState(0);
  const [authUserId, setAuthUserId] = useState<string | null | undefined>(undefined);

  const loadIdentity = useCallback(async () => {
    try {
      if (APP_MODE === 'demo') {
        const local = store as LocalStore;
        await local.init();
        const current = local.persona;
        setUser(current === 'visitor' ? null : { ...DEMO_USERS[current] });
        setAccess(await local.rpc('my_access'));
      } else if (supabase) {
        const { data } = await supabase.auth.getUser();
        if (!data.user) {
          setUser(null);
          setAccess(NO_ACCESS);
        } else {
          const [result, profiles] = await Promise.all([
            store.rpc('my_access').catch(() => ({ ...NO_ACCESS, authenticated: true })),
            store.list('profiles', { eq: { id: data.user.id } }).catch(() => []),
          ]);
          setUser({
            id: data.user.id,
            email: data.user.email ?? null,
            name: profiles[0]?.full_name || (data.user.user_metadata?.full_name as string | undefined) || data.user.email?.split('@')[0] || 'Convidado',
          });
          setAccess(result);
        }
      }
    } finally {
      setVersion((v) => v + 1);
      setReady(true);
    }
  }, [store, supabase]);

  // modo demonstração: persona escolhida fica guardada
  useEffect(() => {
    if (APP_MODE !== 'demo') return;
    const saved = safeStorage.get(PERSONA_KEY) as Persona | null;
    const initial: Persona = saved && ['admin', 'member', 'visitor'].includes(saved) ? saved : 'admin';
    (store as LocalStore).persona = initial;
    setPersonaState(initial);
    void loadIdentity();
  }, [store, loadIdentity]);

  // Supabase: acompanha login/logout. O callback só atualiza estado (sem chamadas ao Supabase dentro dele).
  useEffect(() => {
    if (!supabase) return;
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      setAuthUserId(session?.user?.id ?? null);
    });
    return () => data.subscription.unsubscribe();
  }, [supabase]);

  useEffect(() => {
    if (!supabase || authUserId === undefined) return;
    void loadIdentity();
  }, [supabase, authUserId, loadIdentity]);

  useEffect(() => {
    if (APP_MODE === 'setup') setReady(true);
  }, []);

  const setPersona = useCallback(
    (next: Persona) => {
      if (APP_MODE !== 'demo') return;
      (store as LocalStore).persona = next;
      safeStorage.set(PERSONA_KEY, next);
      setPersonaState(next);
      setReady(false);
      void loadIdentity();
    },
    [store, loadIdentity],
  );

  const signOut = useCallback(async () => {
    if (APP_MODE === 'demo') setPersona('visitor');
    else if (supabase) await supabase.auth.signOut();
  }, [supabase, setPersona]);

  const resetDemo = useCallback(() => {
    if (APP_MODE !== 'demo') return;
    LocalStore.clear();
    safeStorage.remove(PERSONA_KEY);
    window.location.assign('/');
  }, []);

  const value = useMemo<SessionValue>(
    () => ({
      mode: APP_MODE,
      ready,
      user,
      access,
      store,
      key: `${APP_MODE}:${user?.id ?? 'anon'}:${version}`,
      supabase,
      persona,
      setPersona,
      refresh: loadIdentity,
      signOut,
      resetDemo,
    }),
    [ready, user, access, store, version, supabase, persona, setPersona, loadIdentity, signOut, resetDemo],
  );

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession(): SessionValue {
  const value = useContext(SessionContext);
  if (!value) throw new Error('useSession precisa estar dentro de <SessionProvider>.');
  return value;
}
