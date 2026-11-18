/**
 * Regras editoriais compartilhadas pelo painel e pelo armazenamento local de demonstração.
 */
import type { Recipe, RecipeStatus } from './types';

export class AppError extends Error {
  constructor(public code: string, message: string) {
    super(message);
    this.name = 'AppError';
  }
}

export interface TransitionContext {
  openFlags: number;
  permission: string | null;
  linkedUnpublished: number;
  userId: string | null;
  now: string;
}

export function checkRecipeTransition(recipe: Recipe, next: RecipeStatus, ctx: TransitionContext): Partial<Recipe> {
  const patch: Partial<Recipe> = { status: next };

  if (next === 'approved' || next === 'published') {
    if (recipe.content_state !== 'structured') {
      throw new AppError('CONTENT_REQUIRED', 'Estruture ingredientes e etapas antes de disponibilizar a receita.');
    }
    if (ctx.openFlags > 0) {
      throw new AppError('FLAGS_PENDING', 'Resolva os apontamentos de revisão antes de disponibilizar a receita.');
    }
  }

  if (next === 'approved') {
    patch.reviewed_at = ctx.now;
    patch.reviewed_by = ctx.userId ?? recipe.reviewed_by;
  }

  if (next === 'published') {
    if (ctx.permission !== 'confirmed') {
      throw new AppError('PERMISSION_REQUIRED', 'Confirme a permissão comercial da fonte antes de disponibilizar a receita.');
    }
    if (ctx.linkedUnpublished > 0) {
      throw new AppError('LINKED_COMPONENT_UNPUBLISHED', 'Publique os componentes vinculados antes de disponibilizar a receita.');
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

export function statusActions(status: RecipeStatus): StatusAction[] {
  switch (status) {
    case 'draft':
    case 'review':
    case 'approved':
      return [{ to: 'published', label: 'Disponibilizar aos assinantes', tone: 'primary' }, { to: 'archived', label: 'Arquivar', tone: 'default' }];
    case 'published':
      return [{ to: 'archived', label: 'Retirar da biblioteca', tone: 'danger' }];
    case 'archived':
      return [{ to: 'published', label: 'Disponibilizar aos assinantes', tone: 'primary' }];
    default:
      return [];
  }
}

/** Traduz erros do banco/servidor em mensagens para a pessoa. */
export function toAppError(error: unknown): AppError {
  if (error instanceof AppError) return error;
  const raw = error as { message?: string; code?: string } | null;
  const message = raw?.message ?? String(error);
  const tagged = message.match(/^([A-Z][A-Z_]+):\\s*(.*)$/s);
  if (tagged) return new AppError(tagged[1], tagged[2] ? tagged[2].charAt(0).toLocaleUpperCase('pt-BR') + tagged[2].slice(1) : tagged[1]);
  if (/^[A-Z][A-Z_]+$/.test(message)) return new AppError(message, FRIENDLY[message] ?? message);
  const code = raw?.code ?? '';
  if (code === '42501' || /row-level security|permission denied/i.test(message)) return new AppError('FORBIDDEN', 'Você não tem permissão para esta ação.');
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
  CONTENT_REQUIRED: 'Estruture ingredientes e etapas antes de disponibilizar a receita.',
  FLAGS_PENDING: 'Resolva os apontamentos de revisão antes de disponibilizar a receita.',
  PERMISSION_REQUIRED: 'Confirme a permissão comercial da fonte antes de disponibilizar a receita.',
  LINKED_COMPONENT_UNPUBLISHED: 'Publique os componentes vinculados antes de disponibilizar a receita.',
};
