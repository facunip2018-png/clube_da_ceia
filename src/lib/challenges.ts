/**
 * Progresso dos desafios. Mesma regra da função SQL refresh_my_challenges()
 * (usada no modo demonstração; no Supabase quem calcula é o banco).
 */
import type { Challenge, CookingSession, MealPlan, PlanRecipe, PlanTask, RecipeFavorite, ShoppingItem, ShoppingList, UserChallenge } from './types';

export interface ChallengeFacts {
  sessions: Pick<CookingSession, 'recipe_id' | 'status'>[];
  /** recipe_id → slug da coleção */
  collectionSlugByRecipe: Map<string, string>;
  plans: Pick<MealPlan, 'id' | 'event_date'>[];
  planRecipes: Pick<PlanRecipe, 'plan_id'>[];
  planTasks: Pick<PlanTask, 'plan_id' | 'is_done'>[];
  lists: Pick<ShoppingList, 'id'>[];
  items: Pick<ShoppingItem, 'list_id' | 'is_checked'>[];
  favorites: Pick<RecipeFavorite, 'recipe_id'>[];
  userMessages: number;
}

export function challengeTarget(challenge: Pick<Challenge, 'rule_config'>): number {
  return Math.max(1, Math.trunc(Number(challenge.rule_config?.target ?? 1)) || 1);
}

/** Progresso bruto de um desafio; null para desafios manuais. */
export function computeProgress(challenge: Pick<Challenge, 'rule_type' | 'rule_config'>, facts: ChallengeFacts): number | null {
  const finished = facts.sessions.filter((s) => s.status === 'finished');
  switch (challenge.rule_type) {
    case 'cook_any':
      return new Set(finished.map((s) => s.recipe_id)).size;
    case 'cook_in_collection':
      return new Set(
        finished.filter((s) => facts.collectionSlugByRecipe.get(s.recipe_id) === challenge.rule_config.collection_slug).map((s) => s.recipe_id),
      ).size;
    case 'create_plan':
      return facts.plans.filter((p) => p.event_date && facts.planRecipes.some((r) => r.plan_id === p.id)).length;
    case 'complete_plan':
      return facts.plans.filter((p) => {
        const tasks = facts.planTasks.filter((t) => t.plan_id === p.id);
        return tasks.length > 0 && tasks.every((t) => t.is_done);
      }).length;
    case 'shopping_done': {
      const min = Math.max(1, Math.trunc(Number(challenge.rule_config?.min_items ?? 1)) || 1);
      return facts.lists.filter((l) => {
        const items = facts.items.filter((i) => i.list_id === l.id);
        return items.length >= min && items.every((i) => i.is_checked);
      }).length;
    }
    case 'favorites':
      return facts.favorites.length;
    case 'chef_chat':
      return facts.userMessages;
    default:
      return null;
  }
}

export type ChallengeProgress = Pick<UserChallenge, 'challenge_id' | 'progress' | 'target' | 'completed_at' | 'points_awarded'>;

/** Atualiza o progresso preservando conquistas já concluídas. */
export function refreshChallenges(challenges: Challenge[], existing: ChallengeProgress[], facts: ChallengeFacts, now: Date): ChallengeProgress[] {
  const result: ChallengeProgress[] = [];
  for (const challenge of challenges.filter((c) => c.is_active)) {
    const previous = existing.find((e) => e.challenge_id === challenge.id);
    if (previous?.completed_at) {
      result.push(previous);
      continue;
    }
    const raw = computeProgress(challenge, facts);
    if (raw == null) {
      if (previous) result.push(previous);
      continue;
    }
    const target = challengeTarget(challenge);
    const progress = Math.min(raw, target);
    const completed = progress >= target;
    result.push({
      challenge_id: challenge.id,
      progress,
      target,
      completed_at: completed ? now.toISOString() : null,
      points_awarded: completed ? challenge.points : 0,
    });
  }
  return result;
}

export const totalPoints = (progress: Pick<UserChallenge, 'points_awarded'>[]) => progress.reduce((sum, p) => sum + p.points_awarded, 0);

export const TIER_LABELS: Record<string, string> = { bronze: 'Bronze', prata: 'Prata', ouro: 'Ouro' };
