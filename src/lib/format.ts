/** Formatação pt-BR de quantidades, tempos, datas e valores. Sem conversão de unidades. */

const METRIC = new Set(['g', 'kg', 'mg', 'ml', 'l']);
const FRACTIONS: [number, string][] = [
  [1 / 4, '¼'],
  [1 / 3, '⅓'],
  [1 / 2, '½'],
  [2 / 3, '⅔'],
  [3 / 4, '¾'],
];
const PLURALS: Record<string, string> = {
  pacote: 'pacotes', unidade: 'unidades', lata: 'latas', caixinha: 'caixinhas', caixa: 'caixas', 'xícara': 'xícaras',
  'xícara (chá)': 'xícaras (chá)', colher: 'colheres', 'colher (sopa)': 'colheres (sopa)', 'colher (chá)': 'colheres (chá)',
  'colher (café)': 'colheres (café)', copo: 'copos', pitada: 'pitadas', fatia: 'fatias', dente: 'dentes', gema: 'gemas',
  clara: 'claras', ovo: 'ovos', folha: 'folhas', tablete: 'tabletes', barra: 'barras', 'sachê': 'sachês',
  envelope: 'envelopes', travessa: 'travessas', receita: 'receitas', 'porção': 'porções', pote: 'potes', vidro: 'vidros',
  ramo: 'ramos', forma: 'formas',
};

const number = (max: number) => new Intl.NumberFormat('pt-BR', { maximumFractionDigits: max });

export const isMetricUnit = (unit: string | null | undefined) => Boolean(unit && METRIC.has(unit.toLowerCase()));

export function formatNumber(value: number, unit?: string | null): string {
  if (isMetricUnit(unit)) {
    return value >= 10 ? number(0).format(Math.round(value)) : number(1).format(value);
  }
  const whole = Math.floor(value + 1e-9);
  const fraction = value - whole;
  if (fraction < 0.02) return number(0).format(whole);
  if (fraction > 0.98) return number(0).format(whole + 1);
  const match = FRACTIONS.find(([f]) => Math.abs(f - fraction) < 0.02);
  if (match) return whole > 0 ? `${number(0).format(whole)} ${match[1]}` : match[1];
  return number(2).format(value);
}

export function unitLabel(unit: string | null | undefined, quantity: number): string {
  if (!unit) return '';
  if (isMetricUnit(unit)) return unit;
  return quantity >= 2 ? PLURALS[unit] ?? unit : unit;
}

export function formatQuantity(quantity: number, unit?: string | null, quantityMax?: number | null): string {
  const value = quantityMax != null && quantityMax > quantity
    ? `${formatNumber(quantity, unit)} a ${formatNumber(quantityMax, unit)}`
    : formatNumber(quantity, unit);
  const label = unitLabel(unit, quantityMax ?? quantity);
  return label ? `${value} ${label}` : value;
}

/** "4 min", "6 h", "1 h 30 min", "45 s" */
export function formatDuration(totalSeconds: number): string {
  const seconds = Math.max(0, Math.round(totalSeconds));
  if (seconds < 60) return `${seconds} s`;
  const h = Math.floor(seconds / 3600);
  const m = Math.round((seconds % 3600) / 60);
  if (h === 0) return `${m} min`;
  return m === 0 ? `${h} h` : `${h} h ${m} min`;
}

export const formatMinutes = (minutes: number) => formatDuration(minutes * 60);

/** Relógio regressivo: "04:00", "5:59:59" */
export function formatClock(ms: number): string {
  const total = Math.max(0, Math.ceil(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const pad = (n: number) => String(n).padStart(2, '0');
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`;
}

export function formatMoney(cents: number, currency = 'BRL'): string {
  return new Intl.NumberFormat('pt-BR', { style: 'currency', currency }).format(cents / 100);
}

const TZ = 'America/Sao_Paulo';

export function formatDate(value: string | Date, options: Intl.DateTimeFormatOptions = { day: '2-digit', month: 'long', year: 'numeric' }): string {
  // datas puras (AAAA-MM-DD) são tratadas como dia civil, sem deslocamento de fuso
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)) {
    const [y, m, d] = value.split('-').map(Number);
    return new Intl.DateTimeFormat('pt-BR', { ...options, timeZone: 'UTC' }).format(new Date(Date.UTC(y, m - 1, d)));
  }
  return new Intl.DateTimeFormat('pt-BR', { ...options, timeZone: TZ }).format(new Date(value));
}

export function formatDateTime(value: string | Date): string {
  return new Intl.DateTimeFormat('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', timeZone: TZ }).format(new Date(value));
}

/** minúsculas e sem acentos, para busca e comparação */
export function normalizeText(text: string): string {
  return text.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim();
}

export function pageRange(start: number | null, end?: number | null): string | null {
  if (!start) return null;
  return end && end !== start ? `p. ${start}–${end}` : `p. ${start}`;
}

export function initials(name: string | null | undefined, fallback = 'C'): string {
  const parts = (name ?? '').trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return fallback;
  return (parts[0][0] + (parts.length > 1 ? parts[parts.length - 1][0] : '')).toUpperCase();
}
