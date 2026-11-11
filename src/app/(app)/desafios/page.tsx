'use client';

import { useRef, useState } from 'react';
import { Award, Cake, CalendarHeart, Camera, Check, ChefHat, Croissant, Heart, ListChecks, Medal, Sandwich, ShoppingBasket, Sparkles, Trophy, type LucideIcon } from 'lucide-react';
import { invalidate, useRpc, useTable } from '@/data/hooks';
import { useSession } from '@/data/session';
import { Guard } from '@/components/gates';
import { useToast } from '@/components/toast';
import { Loading, PageHead, Progress, usePageTitle } from '@/components/ui';
import { challengeTarget, TIER_LABELS, totalPoints } from '@/lib/challenges';
import { newId } from '@/lib/safe-storage';
import type { Challenge } from '@/lib/types';

const ICONS: Record<string, LucideIcon> = {
  croissant: Croissant, sandwich: Sandwich, cake: Cake, 'chef-hat': ChefHat, calendar: CalendarHeart, 'list-checks': ListChecks,
  'shopping-basket': ShoppingBasket, heart: Heart, sparkles: Sparkles,
};
const PHOTO_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
const MAX_PHOTO_BYTES = 5 * 1024 * 1024;

function Challenges() {
  const { store, supabase, user } = useSession();
  const { toast, fail } = useToast();
  const { rows: challenges, loading } = useTable('challenges', { order: [['position', 'asc']] });
  const { data: progress } = useRpc('refresh_my_challenges');
  const { rows: submissions } = useTable('challenge_submissions', user ? { eq: { user_id: user.id } } : null);
  const fileInput = useRef<HTMLInputElement>(null);
  const [target, setTarget] = useState<Challenge | null>(null);
  const [uploading, setUploading] = useState(false);

  if (loading || !challenges) return <Loading />;
  const active = challenges.filter((c) => c.is_active);
  const of = (id: string) => progress?.find((p) => p.challenge_id === id);
  const completed = active.filter((c) => of(c.id)?.completed_at);
  const points = totalPoints(progress ?? []);
  const possible = active.reduce((sum, c) => sum + c.points, 0);

  async function onFile(file: File | undefined) {
    if (!file || !target || !user) return;
    if (!PHOTO_TYPES.includes(file.type)) return fail(new Error('Envie uma foto em JPG, PNG ou WebP.'));
    if (file.size > MAX_PHOTO_BYTES) return fail(new Error('A foto deve ter no máximo 5 MB.'));
    if (!supabase) return fail(new Error('O envio de fotos fica disponível com o Supabase conectado.'));
    setUploading(true);
    try {
      const extension = file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : 'jpg';
      const path = `${user.id}/${newId()}.${extension}`;
      const { error } = await supabase.storage.from('challenge-photos').upload(path, file, { contentType: file.type, upsert: false });
      if (error) throw error;
      await store.insert('challenge_submissions', { challenge_id: target.id, photo_path: path });
      await invalidate('challenge_submissions');
      toast('Foto enviada! Ela fica visível só para você e para a curadoria.');
    } catch (error) {
      fail(error);
    } finally {
      setUploading(false);
      setTarget(null);
      if (fileInput.current) fileInput.current.value = '';
    }
  }

  return (
    <>
      <div className="scorecard">
        <div>
          <div className="eyebrow" style={{ color: '#e2c987' }}>✦ Sua pontuação</div>
          <div className="row" style={{ alignItems: 'baseline', marginTop: 8 }}>
            <span className="big">{points}</span>
            <span style={{ color: '#cdd9cf' }}>de {possible} pontos · {completed.length}/{active.length} desafios</span>
          </div>
        </div>
        <div>
          <div className="eyebrow" style={{ color: '#e2c987', marginBottom: 8 }}>Medalhas</div>
          <div className="medals">
            {active.map((c) => {
              const done = Boolean(of(c.id)?.completed_at);
              return (
                <div key={c.id} className={`medal ${done ? `on ${c.badge_tier ?? 'bronze'}` : ''}`} title={`${c.badge_name ?? c.title}${done ? ' — conquistada' : ''}`} role="img" aria-label={`${c.badge_name ?? c.title}${done ? ' — conquistada' : ' — bloqueada'}`}>
                  {c.badge_tier === 'ouro' ? <Trophy /> : c.badge_tier === 'prata' ? <Award /> : <Medal />}
                </div>
              );
            })}
          </div>
        </div>
      </div>

      <div className="challengegrid" style={{ marginTop: 18 }}>
        {active.map((challenge) => {
          const state = of(challenge.id);
          const goal = state?.target ?? challengeTarget(challenge);
          const value = Math.min(state?.progress ?? 0, goal);
          const done = Boolean(state?.completed_at);
          const Icon = ICONS[challenge.icon ?? ''] ?? Trophy;
          const sent = submissions?.filter((s) => s.challenge_id === challenge.id).length ?? 0;
          return (
            <article key={challenge.id} className={`challenge ${done ? 'done' : ''}`}>
              <div className="spread">
                <div className="challengeicon"><Icon /></div>
                <span className={`pill ${done ? 'ok' : 'gold'}`}>{done ? <><Check /> Concluído</> : `${challenge.points} pontos`}</span>
              </div>
              <h3>{challenge.title}</h3>
              <p>{challenge.description}</p>
              <Progress value={goal ? value / goal : 0} label={`Progresso de ${challenge.title}`} />
              <div className="spread muted small">
                <span>{value}/{goal}</span>
                {challenge.badge_name && <span>{challenge.badge_name}{challenge.badge_tier ? ` · ${TIER_LABELS[challenge.badge_tier]}` : ''}</span>}
              </div>
              {challenge.allows_photo && done && (
                <button type="button" className="btn outline sm" disabled={uploading} onClick={() => { setTarget(challenge); fileInput.current?.click(); }}>
                  <Camera /> {sent ? `Enviar outra foto (${sent} enviada${sent > 1 ? 's' : ''})` : 'Enviar foto do resultado (opcional)'}
                </button>
              )}
            </article>
          );
        })}
      </div>
      <input ref={fileInput} type="file" accept={PHOTO_TYPES.join(',')} hidden onChange={(e) => onFile(e.target.files?.[0])} />
      <p className="muted small" style={{ marginTop: 16 }}>
        O progresso é calculado automaticamente a partir do que você faz no Clube: receitas concluídas no modo cozinheiro, planejamento da ceia, lista de compras, favoritas e conversas com o Chef.
      </p>
    </>
  );
}

export default function ChallengesPage() {
  usePageTitle('Desafios');
  return (
    <>
      <PageHead eyebrow="Aprenda, prepare e conquiste" title="Desafios da temporada." sub="Pequenas missões para transformar a cozinha em parte da celebração." />
      <Guard what="O progresso nos desafios">
        <Challenges />
      </Guard>
    </>
  );
}
