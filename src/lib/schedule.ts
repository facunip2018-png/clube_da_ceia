/**
 * Cronograma de preparo da ceia.
 *
 * Trabalha de trás para frente a partir do horário de servir e usa APENAS os tempos
 * cadastrados nas fichas (temporizadores). Como os materiais raramente informam o tempo
 * de mão na massa, cada parte da receita recebe um "bloco de organização" configurável
 * pela pessoa (padrão 30 min) — claramente identificado como estimativa dela, não da receita.
 * O cálculo é conservador: partes e esperas são consideradas em sequência.
 */
import type { RecipeDetail } from './types';
import { formatDuration } from './format';

export interface ScheduleInput {
  eventDate: string; // AAAA-MM-DD
  serveTime: string | null; // HH:MM
  blockMinutes: number;
  recipes: { detail: RecipeDetail; factor: number }[];
}

export interface ScheduleEntry {
  key: string;
  at: Date;
  kind: 'start' | 'wait' | 'serve';
  title: string;
  detail: string | null;
  recipeId: string | null;
  /** true quando o horário depende do bloco de organização (estimativa da pessoa) */
  estimated: boolean;
}

export interface Schedule {
  serveAt: Date;
  entries: ScheduleEntry[];
  /** receitas do cardápio sem ficha disponível (sem tempos para calcular) */
  withoutTimes: string[];
}

export const DEFAULT_SERVE_TIME = '20:00';

export function parseLocalDateTime(date: string, time: string | null): Date {
  const [y, m, d] = date.split('-').map(Number);
  const [hh, mm] = (time ?? DEFAULT_SERVE_TIME).split(':').map(Number);
  return new Date(y, m - 1, d, hh || 0, mm || 0, 0, 0);
}

const minutes = (n: number) => n * 60_000;

export function buildSchedule(input: ScheduleInput): Schedule {
  const serveAt = parseLocalDateTime(input.eventDate, input.serveTime);
  const entries: ScheduleEntry[] = [];
  const withoutTimes: string[] = [];
  const block = Math.max(0, input.blockMinutes);

  for (const { detail } of input.recipes) {
    const { recipe } = detail;
    if (!detail.hasContent) {
      withoutTimes.push(recipe.title);
      continue;
    }

    // percorre as partes de trás para frente, acumulando a partir do horário de servir
    let cursor = serveAt.getTime();
    let activeSeconds = 0;
    let passiveSeconds = 0;
    const waits: ScheduleEntry[] = [];

    for (const part of [...detail.parts].reverse()) {
      for (const step of [...part.steps].reverse()) {
        for (const timer of [...step.timers].reverse()) {
          const duration = timer.duration_seconds * 1000;
          cursor -= duration;
          if (timer.kind === 'chill' || timer.kind === 'rest') {
            passiveSeconds += timer.duration_seconds;
            if (timer.duration_seconds >= 30 * 60) {
              waits.push({
                key: `wait:${recipe.id}:${timer.id}`,
                at: new Date(cursor),
                kind: 'wait',
                title: `${recipe.title}: ${timer.label.toLocaleLowerCase('pt-BR')}`,
                detail: `${timer.is_minimum ? 'Mínimo de ' : ''}${formatDuration(timer.duration_seconds)} — comece esta espera até este horário.`,
                recipeId: recipe.id,
                estimated: block > 0,
              });
            }
          } else {
            activeSeconds += timer.duration_seconds;
          }
        }
      }
      cursor -= minutes(block);
    }

    const pieces: string[] = [];
    if (activeSeconds > 0) pieces.push(`${formatDuration(activeSeconds)} de fogo/forno`);
    if (passiveSeconds > 0) pieces.push(`${formatDuration(passiveSeconds)} de geladeira/descanso`);
    const registered = pieces.length ? `Tempos da ficha: ${pieces.join(' + ')}.` : 'A ficha não informa tempos de preparo.';
    const blocks = block > 0 ? ` Inclui ${detail.parts.length} bloco${detail.parts.length > 1 ? 's' : ''} de organização de ${block} min (estimativa sua).` : '';

    entries.push({
      key: `start:${recipe.id}`,
      at: new Date(cursor),
      kind: 'start',
      title: `Começar: ${recipe.title}`,
      detail: registered + blocks,
      recipeId: recipe.id,
      estimated: block > 0,
    });
    entries.push(...waits);
  }

  entries.push({ key: 'serve', at: serveAt, kind: 'serve', title: 'Servir a ceia', detail: null, recipeId: null, estimated: false });
  entries.sort((a, b) => a.at.getTime() - b.at.getTime());
  return { serveAt, entries, withoutTimes };
}

export interface DefaultTask {
  ref_key: string;
  title: string;
  daysBefore: number;
}

/** Checklist de organização (tarefas genéricas de anfitrião — não são conteúdo de receita). */
export const DEFAULT_TASKS: DefaultTask[] = [
  { ref_key: 'default:cardapio', title: 'Confirmar convidados e fechar o cardápio', daysBefore: 7 },
  { ref_key: 'default:lista', title: 'Gerar a lista de compras a partir do cardápio', daysBefore: 5 },
  { ref_key: 'default:compras', title: 'Fazer as compras de itens não perecíveis', daysBefore: 4 },
  { ref_key: 'default:frescos', title: 'Comprar os itens frescos e conferir travessas e utensílios', daysBefore: 2 },
  { ref_key: 'default:adiantar', title: 'Adiantar os preparos que pedem geladeira ou descanso', daysBefore: 1 },
  { ref_key: 'default:mesa', title: 'Finalizar as receitas e montar a mesa', daysBefore: 0 },
];

export function defaultTaskDueDate(eventDate: string, daysBefore: number): string {
  const [y, m, d] = eventDate.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d - daysBefore, 12));
  return date.toISOString();
}

/** Dias até o evento, contando por dia civil. */
export function daysUntil(eventDate: string, today = new Date()): number {
  const [y, m, d] = eventDate.split('-').map(Number);
  const a = Date.UTC(y, m - 1, d);
  const b = Date.UTC(today.getFullYear(), today.getMonth(), today.getDate());
  return Math.round((a - b) / 86_400_000);
}
