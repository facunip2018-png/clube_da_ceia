/**
 * Modo de funcionamento do app, definido por variáveis de ambiente públicas.
 *   supabase → produção: login, banco e permissões reais
 *   demo     → demonstração local, sem servidor (NUNCA usar em produção: expõe o catálogo de exemplo)
 *   setup    → nada configurado: mostra as instruções de configuração
 */
export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? '';
export const SUPABASE_ANON_KEY =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? '';

export type AppMode = 'supabase' | 'demo' | 'setup';

export const APP_MODE: AppMode =
  SUPABASE_URL && SUPABASE_ANON_KEY ? 'supabase' : process.env.NEXT_PUBLIC_DEMO_MODE === 'true' ? 'demo' : 'setup';

export const APP_NAME = 'Clube da Ceia Perfeita';
export const APP_TAGLINE = 'Natal & Ano-Novo';
