'use client';

import { createContext, useCallback, useContext, useMemo, useState, type FormEvent, type ReactNode } from 'react';
import { Sheet } from './ui';

/**
 * Confirmações e perguntas dentro do próprio app.
 * Não usamos window.confirm/prompt: navegadores bloqueiam esses diálogos quando o app
 * roda embutido (pré-visualizações) e eles destoam da identidade visual.
 */
interface ConfirmOptions {
  title: string;
  message?: ReactNode;
  confirmLabel?: string;
  danger?: boolean;
}
interface PromptOptions extends ConfirmOptions {
  label: string;
  defaultValue?: string;
  placeholder?: string;
  required?: boolean;
}
interface DialogApi {
  confirm: (options: ConfirmOptions) => Promise<boolean>;
  /** devolve o texto digitado, ou null se a pessoa cancelar */
  ask: (options: PromptOptions) => Promise<string | null>;
}

type Pending =
  | { kind: 'confirm'; options: ConfirmOptions; resolve: (value: boolean) => void }
  | { kind: 'ask'; options: PromptOptions; resolve: (value: string | null) => void };

const DialogContext = createContext<DialogApi | null>(null);

export function DialogProvider({ children }: { children: ReactNode }) {
  const [pending, setPending] = useState<Pending | null>(null);
  const [value, setValue] = useState('');

  const api = useMemo<DialogApi>(
    () => ({
      confirm: (options) => new Promise<boolean>((resolve) => setPending({ kind: 'confirm', options, resolve })),
      ask: (options) =>
        new Promise<string | null>((resolve) => {
          setValue(options.defaultValue ?? '');
          setPending({ kind: 'ask', options, resolve });
        }),
    }),
    [],
  );

  const cancel = useCallback(() => {
    setPending((current) => {
      if (current?.kind === 'confirm') current.resolve(false);
      if (current?.kind === 'ask') current.resolve(null);
      return null;
    });
  }, []);

  function accept(event: FormEvent) {
    event.preventDefault();
    if (!pending) return;
    if (pending.kind === 'confirm') pending.resolve(true);
    else {
      if (pending.options.required && !value.trim()) return;
      pending.resolve(value.trim());
    }
    setPending(null);
  }

  return (
    <DialogContext.Provider value={api}>
      {children}
      {pending && (
        <Sheet title={pending.options.title} onClose={cancel}>
          <form className="stack" onSubmit={accept}>
            {pending.options.message && <p className="sub">{pending.options.message}</p>}
            {pending.kind === 'ask' && (
              <div className="group">
                <label htmlFor="dialog-input">{pending.options.label}</label>
                <input id="dialog-input" className="field" value={value} onChange={(e) => setValue(e.target.value)} placeholder={pending.options.placeholder} autoFocus maxLength={240} />
              </div>
            )}
            <div className="row" style={{ justifyContent: 'flex-end' }}>
              <button type="button" className="btn outline" onClick={cancel}>Cancelar</button>
              <button type="submit" className={`btn ${pending.options.danger ? 'danger' : 'dark'}`} autoFocus={pending.kind === 'confirm'}>
                {pending.options.confirmLabel ?? 'Confirmar'}
              </button>
            </div>
          </form>
        </Sheet>
      )}
    </DialogContext.Provider>
  );
}

export function useDialog(): DialogApi {
  const api = useContext(DialogContext);
  if (!api) throw new Error('useDialog precisa estar dentro de <DialogProvider>.');
  return api;
}
