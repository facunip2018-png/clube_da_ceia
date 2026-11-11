'use client';

import { createContext, useCallback, useContext, useMemo, useRef, useState, type ReactNode } from 'react';
import { CircleAlert, CircleCheck } from 'lucide-react';
import { toAppError } from '@/lib/editorial';

interface ToastItem {
  id: number;
  message: string;
  type: 'ok' | 'error';
  action?: { label: string; onClick: () => void };
}

interface ToastApi {
  toast: (message: string, options?: { action?: ToastItem['action'] }) => void;
  /** mostra o erro de forma amigável */
  fail: (error: unknown) => void;
}

const ToastContext = createContext<ToastApi | null>(null);

export function ToastProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<ToastItem[]>([]);
  const seq = useRef(0);

  const push = useCallback((item: Omit<ToastItem, 'id'>) => {
    const id = ++seq.current;
    setItems((current) => [...current.slice(-2), { ...item, id }]);
    window.setTimeout(() => setItems((current) => current.filter((t) => t.id !== id)), item.type === 'error' ? 6000 : 3600);
  }, []);

  const api = useMemo<ToastApi>(
    () => ({
      toast: (message, options) => push({ message, type: 'ok', action: options?.action }),
      fail: (error) => push({ message: toAppError(error).message, type: 'error' }),
    }),
    [push],
  );

  return (
    <ToastContext.Provider value={api}>
      {children}
      <div className="toasts" role="status" aria-live="polite">
        {items.map((item) => (
          <div key={item.id} className={`toast ${item.type === 'error' ? 'error' : ''}`}>
            {item.type === 'error' ? <CircleAlert /> : <CircleCheck />}
            <span>{item.message}</span>
            {item.action && (
              <button
                type="button"
                onClick={() => {
                  item.action?.onClick();
                  setItems((current) => current.filter((t) => t.id !== item.id));
                }}
              >
                {item.action.label}
              </button>
            )}
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast(): ToastApi {
  const api = useContext(ToastContext);
  if (!api) throw new Error('useToast precisa estar dentro de <ToastProvider>.');
  return api;
}
