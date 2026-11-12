/** Transições simples; a liberação de receitas completas é direta. */
export function checkRecipeTransition(recipe: Recipe, next: RecipeStatus, ctx: TransitionContext): Partial<Recipe> {
  const patch: Partial<Recipe> = { status: next };
  if (next === 'published') {
    patch.published_at = recipe.published_at ?? ctx.now;
  }
  if (next === 'approved') {
    patch.reviewed_at = ctx.now;
    patch.reviewed_by = ctx.userId ?? recipe.reviewed_by;
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
