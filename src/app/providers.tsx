'use client';

import { useEffect, type ReactNode } from 'react';
import { SessionProvider, useSession } from '@/data/session';
import { ToastProvider } from '@/components/toast';
import { TimerProvider } from '@/components/timers';
import { DialogProvider } from '@/components/dialogs';
import { SetupScreen } from '@/components/gates';

function ModeGate({ children }: { children: ReactNode }) {
  const { mode } = useSession();
  if (mode === 'setup') return <SetupScreen />;
  return <>{children}</>;
}

export function Providers({ children }: { children: ReactNode }) {
  // Service worker: só em produção e fora de iframes (pré-visualizações embutidas não registram).
  useEffect(() => {
    if (process.env.NODE_ENV !== 'production' || !('serviceWorker' in navigator)) return;
    let framed = false;
    try {
      framed = window.self !== window.top;
    } catch {
      framed = true;
    }
    if (!framed) navigator.serviceWorker.register('/sw.js', { scope: '/', updateViaCache: 'none' }).catch(() => undefined);
  }, []);

  return (
    <SessionProvider>
      <ToastProvider>
        <DialogProvider>
          <TimerProvider>
            <ModeGate>{children}</ModeGate>
          </TimerProvider>
        </DialogProvider>
      </ToastProvider>
    </SessionProvider>
  );
}
