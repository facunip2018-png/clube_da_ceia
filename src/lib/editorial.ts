/**
 * Valida as transições editoriais antes de aprovar ou publicar uma receita.
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

  if ((next === 'approved' || next === 'published') && ctx.openFlags > 0) {
    throw new AppError('FLAGS_PENDING', 'Resolva os pontos de revisão antes de continuar.');
  }

  if (next === 'published') {
    // Receitas arquivadas podem voltar ao ar sem nova aprovação quando já foram revisadas.
    if (!recipe.reviewed_at) {
      throw new AppError('APPROVAL_REQUIRED', 'A receita precisa ser aprovada antes da publicação.');
    }
    if (ctx.permission !== 'confirmed') {
      throw new AppError('PERMISSION_REQUIRED', 'Confirme a permissão comercial da fonte antes da publicação.');
    }
    if (ctx.linkedUnpublished > 0) {
      throw new AppError('LINKED_RECIPE_UNPUBLISHED', 'Publique ou remova as partes vinculadas que ainda não estão publicadas.');
    }
    patch.published_at = recipe.published_at ?? ctx.now;
  }

  if (next === 'approved') {
    patch.reviewed_at = recipe.reviewed_at ?? ctx.now;
    patch.reviewed_by = recipe.reviewed_by ?? ctx.userId;
  }

  return patch;
}

export interface StatusAction {
  to: RecipeStatus;
  label: string;
  tone: 'primary' | 'default' | 'danger';
}

export function statusActions(status: RecipeStatus, alreadyReviewed = false): StatusAction[] {
  const approve = (label = 'Aprovar para publicação'): StatusAction => ({ to: 'approved', label, tone: 'primary' });
  const publish = (label = 'Disponibilizar aos assinantes'): StatusAction => ({ to: 'published', label, tone: 'primary' });
  const archive: StatusAction = { to: 'archived', label: 'Arquivar', tone: 'default' };

  switch (status) {
    case 'draft':
    case 'review':
      return [approve(), archive];
    case 'approved':
      return [publish(), archive];
    case 'published':
      return [{ to: 'archived', label: 'Retirar da biblioteca', tone: 'danger' }];
    case 'archived':
      return alreadyReviewed ? [publish('Republicar aos assinantes'), archive] : [approve('Revisar antes de republicar')];
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
  FLAGS_PENDING: 'Resolva os pontos de revisão antes de continuar.',
  APPROVAL_REQUIRED: 'A receita precisa ser aprovada antes da publicação.',
  PERMISSION_REQUIRED: 'Confirme a permissão comercial da fonte antes da publicação.',
  LINKED_RECIPE_UNPUBLISHED: 'Publique ou remova as partes vinculadas que ainda não estão publicadas.',
};
