'use client';

import Image from 'next/image';
import Link from 'next/link';
import { useEffect, type ReactNode } from 'react';
import { Info, Minus, Plus, TriangleAlert, Utensils, X, type LucideIcon } from 'lucide-react';
import { APP_NAME } from '@/lib/env';

export function usePageTitle(title: string | null | undefined) {
  useEffect(() => {
    if (title) document.title = `${title} · ${APP_NAME}`;
  }, [title]);
}

/** Foto de capa. Imagens locais passam pelo otimizador do Next; URLs externas (Storage) são carregadas direto. */
export function Cover({ src, alt, sizes, priority, className }: { src: string | null | undefined; alt: string; sizes: string; priority?: boolean; className?: string }) {
  if (!src) return null;
  if (src.startsWith('/')) return <Image src={src} alt={alt} fill sizes={sizes} priority={priority} className={className} />;
  // eslint-disable-next-line @next/next/no-img-element
  return <img src={src} alt={alt} loading={priority ? 'eager' : 'lazy'} className={className} />;
}

export function Photo({ src, alt, sizes, className = '', children, priority }: { src: string | null | undefined; alt: string; sizes: string; className?: string; children?: ReactNode; priority?: boolean }) {
  return (
    <div className={`photo ${src ? '' : 'placeholder'} ${className}`}>
      {src ? <Cover src={src} alt={alt} sizes={sizes} priority={priority} /> : <Utensils aria-hidden />}
      {children}
    </div>
  );
}

export function PageHead({ eyebrow, title, sub, children, back }: { eyebrow?: string; title: string; sub?: ReactNode; children?: ReactNode; back?: { href: string; label: string } }) {
  return (
    <div className="pagehead">
      <div className="grow">
        {back && (
          <Link href={back.href} className="textbtn" style={{ marginBottom: 10 }}>
            ← {back.label}
          </Link>
        )}
        {eyebrow && <div className="eyebrow">{eyebrow}</div>}
        <h1>{title}</h1>
        {sub && <p className="sub" style={{ maxWidth: 640 }}>{sub}</p>}
      </div>
      {children && <div className="row">{children}</div>}
    </div>
  );
}

export function Notice({ tone = 'gold', children, icon }: { tone?: 'gold' | 'soft' | 'danger'; children: ReactNode; icon?: LucideIcon }) {
  const Icon = icon ?? (tone === 'danger' ? TriangleAlert : Info);
  return (
    <div className={tone === 'soft' ? 'softnotice' : `notice ${tone === 'danger' ? 'danger' : ''}`}>
      <Icon aria-hidden />
      <div>{children}</div>
    </div>
  );
}

export function Empty({ icon: Icon, title, children, action }: { icon: LucideIcon; title: string; children?: ReactNode; action?: ReactNode }) {
  return (
    <div className="empty">
      <div className="ico"><Icon aria-hidden /></div>
      <h3>{title}</h3>
      {children && <p className="sub">{children}</p>}
      {action}
    </div>
  );
}

export function Progress({ value, label }: { value: number; label?: string }) {
  const percent = Math.round(Math.min(1, Math.max(0, value)) * 100);
  return (
    <div className="progress" role="progressbar" aria-valuenow={percent} aria-valuemin={0} aria-valuemax={100} aria-label={label}>
      <span style={{ width: `${percent}%` }} />
    </div>
  );
}

export function Stepper({ value, onChange, min, max, step, label, format }: { value: number; onChange: (v: number) => void; min: number; max: number; step: number; label: string; format: (v: number) => string }) {
  const clamp = (v: number) => Math.min(max, Math.max(min, Math.round(v * 100) / 100));
  return (
    <div className="stepper" role="group" aria-label={label}>
      <button type="button" onClick={() => onChange(clamp(value - step))} disabled={value <= min} aria-label="Diminuir"><Minus /></button>
      <output aria-live="polite">{format(value)}</output>
      <button type="button" onClick={() => onChange(clamp(value + step))} disabled={value >= max} aria-label="Aumentar"><Plus /></button>
    </div>
  );
}

export function Sheet({ title, eyebrow, onClose, children, wide }: { title: string; eyebrow?: string; onClose: () => void; children: ReactNode; wide?: boolean }) {
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => event.key === 'Escape' && onClose();
    document.addEventListener('keydown', onKey);
    const previous = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.removeEventListener('keydown', onKey);
      document.body.style.overflow = previous;
    };
  }, [onClose]);
  return (
    <div className="overlay" onMouseDown={(event) => event.target === event.currentTarget && onClose()}>
      <div className={`sheet ${wide ? 'wide' : ''}`} role="dialog" aria-modal="true" aria-label={title}>
        <div className="sheethead">
          <div>
            {eyebrow && <div className="eyebrow">{eyebrow}</div>}
            <h2 style={{ marginTop: eyebrow ? 6 : 0 }}>{title}</h2>
          </div>
          <button type="button" className="iconbtn" onClick={onClose} aria-label="Fechar"><X /></button>
        </div>
        {children}
      </div>
    </div>
  );
}

export function CardSkeletons({ count = 4, height = 220 }: { count?: number; height?: number }) {
  return (
    <>
      {Array.from({ length: count }, (_, i) => (
        <div key={i} className="skeleton" style={{ height }} />
      ))}
    </>
  );
}

export function Loading({ label = 'Carregando…' }: { label?: string }) {
  return (
    <div className="stack" aria-busy="true" aria-label={label}>
      <div className="skeleton" style={{ height: 34, width: '46%' }} />
      <div className="skeleton" style={{ height: 18, width: '70%' }} />
      <div className="skeleton" style={{ height: 240 }} />
    </div>
  );
}

export function ErrorState({ error, onRetry }: { error: Error | undefined; onRetry?: () => void }) {
  return (
    <Empty icon={TriangleAlert} title="Não foi possível carregar" action={onRetry && <button type="button" className="btn outline sm" onClick={onRetry}>Tentar de novo</button>}>
      {error?.message ?? 'Verifique sua conexão e tente novamente.'}
    </Empty>
  );
}
