/** Regras de venda da temporada (usadas no cliente e no servidor). */
export interface SeasonSaleWindow {
  status: string;
  price_cents: number | null;
  sales_starts_at: string | null;
  sales_ends_at: string | null;
}

/** A temporada está à venda agora? Devolve o motivo quando não está. */
export function saleAvailability(season: SeasonSaleWindow | null | undefined, now = new Date()): { open: boolean; reason: string | null } {
  if (!season) return { open: false, reason: 'Nenhuma temporada disponível.' };
  if (season.status !== 'active') return { open: false, reason: 'A temporada ainda não foi aberta.' };
  if (!season.price_cents || season.price_cents <= 0) return { open: false, reason: 'O valor da temporada ainda não foi definido.' };
  if (season.sales_starts_at && now < new Date(season.sales_starts_at)) return { open: false, reason: 'As vendas desta temporada ainda não começaram.' };
  if (season.sales_ends_at && now > new Date(season.sales_ends_at)) return { open: false, reason: 'As vendas desta temporada foram encerradas.' };
  return { open: true, reason: null };
}
