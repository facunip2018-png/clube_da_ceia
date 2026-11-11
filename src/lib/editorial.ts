/**
 * Fluxo editorial das fichas: draft → review → approved → published.
 * Mesmas regras do gatilho guard_recipe_status() do banco — aqui servem ao modo
 * demonstração e para explicar ao administrador o que falta antes de publicar.
 */
import type { Recipe, RecipeStatus } from './types';

export class AppError extends Error {
  constructor(public code: string, message: string) {
    super(message);
    this.name = 'AppError';
  }
}

export interface TransitionContext {
  /** pontos de revisão em aberto com severidade warning/blocker */
  openFlags: number;
  /** permissão comercial do documento de origem */
  permission: string | null;
  /** componentes compartilhados ainda não publicados */
  linkedUnpublished: number;
  userId: string | null;
  now: string;
}

export function checkRecipeTransition(recipe: Recipe, next: RecipeStatus, ctx: TransitionContext): Partial<Recipe> {
  const patch: Partial<Recipe> = { status: next };
  if (next === recipe.status) return patch;

  if (next === 'approved' || next === 'published') {
    if (recipe.content_state !== 'structured') {
      throw new AppError('CONTENT_REQUIRED', 'A receita ainda não possui ficha estruturada.');
    }
    if (ctx.openFlags > 0) {
      throw new AppError('FLAGS_PENDING', 'Existem pontos de revisão em aberto nesta ficha.');
    }
  }
  if (next === 'approved') {
    patch.reviewed_at = ctx.now;
    patch.reviewed_by = ctx.userId ?? recipe.reviewed_by;
  }
  if (next === 'published') {
    if (!recipe.reviewed_at) {
      throw new AppError('APPROVAL_REQUIRED', 'A ficha precisa ser aprovada na revisão antes de ser publicada.');
    }
    if (ctx.permission !== 'confirmed') {
      throw new AppError('PERMISSION_REQUIRED', 'Confirme a permissão comercial do documento de origem antes de publicar.');
    }
    if (ctx.linkedUnpublished > 0) {
      throw new AppError('LINKED_COMPONENT_UNPUBLISHED', 'Publique antes os componentes compartilhados desta receita.');
    }
    patch.published_at = recipe.published_at ?? ctx.now;
  }
  return patch;
}

export interface StatusAction {
  to: RecipeStatus;
  label: string;
  tone: 'primary' | 'default' | 'danger';
}

/** Próximos passos oferecidos ao administrador em cada situação. */
export function statusActions(status: RecipeStatus): StatusAction[] {
  switch (status) {
    case 'draft':
      return [{ to: 'review', label: 'Enviar para revisão', tone: 'primary' }, { to: 'archived', label: 'Arquivar', tone: 'default' }];
    case 'review':
      return [{ to: 'approved', label: 'Aprovar ficha', tone: 'primary' }, { to: 'draft', label: 'Voltar para rascunho', tone: 'default' }];
    case 'approved':
      return [{ to: 'published', label: 'Publicar', tone: 'primary' }, { to: 'review', label: 'Reabrir revisão', tone: 'default' }];
    case 'published':
      return [{ to: 'review', label: 'Tirar do ar (voltar à revisão)', tone: 'danger' }, { to: 'archived', label: 'Arquivar', tone: 'default' }];
    case 'archived':
      return [{ to: 'draft', label: 'Restaurar como rascunho', tone: 'default' }];
    default:
      return [];
  }
}

/** Traduz erros do banco/servidor em mensagens para a pessoa. */
export function toAppError(error: unknown): AppError {
  if (error instanceof AppError) return error;
  const raw = error as { message?: string; code?: string } | null;
  const message = raw?.message ?? String(error);
  const tagged = message.match(/^([A-Z][A-Z_]+):\s*(.*)$/s);
  if (tagged) return new AppError(tagged[1], tagged[2] ? tagged[2].charAt(0).toLocaleUpperCase('pt-BR') + tagged[2].slice(1) : tagged[1]);
  if (/^[A-Z][A-Z_]+$/.test(message)) return new AppError(message, FRIENDLY[message] ?? message);
  const code = raw?.code ?? '';
  if (code === '42501' || /row-level security|permission denied/i.test(message)) {
    return new AppError('FORBIDDEN', 'Você não tem permissão para esta ação.');
  }
  if (code === '23505') return new AppError('DUPLICATE', 'Este registro já existe.');
  if (code === '23503') return new AppError('IN_USE', 'Este registro está em uso e não pode ser alterado.');
  if (/jwt|not authenticated|session/i.test(message)) return new AppError('NOT_AUTHENTICATED', 'Sua sessão expirou. Entre novamente.');
  if (/failed to fetch|network|load failed/i.test(message)) return new AppError('NETWORK', 'Sem conexão. Verifique a internet e tente de novo.');
  return new AppError('UNKNOWN', message || 'Não foi possível concluir a ação.');
}

const FRIENDLY: Record<string, string> = {
  FORBIDDEN: 'Você não tem permissão para esta ação.',
  NOT_AUTHENTICATED: 'Entre na sua conta para continuar.',
  ACCESS_REQUIRED: 'Este recurso faz parte do acesso da temporada.',
};
