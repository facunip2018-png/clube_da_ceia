'use client';

import { useCallback } from 'react';
import type { RpcName } from '@/data/store';
import type { TableName } from '@/lib/types';
import { invalidate } from '@/data/hooks';
import { useToast } from './toast';

/** Executa uma alteração administrativa, recarrega as tabelas afetadas e mostra o resultado. */
export function useAdminAction() {
  const { toast, fail } = useToast();
  return useCallback(
    async (fn: () => Promise<unknown>, options: { tables: (TableName | RpcName)[]; success?: string }) => {
      try {
        await fn();
        await invalidate(...options.tables, 'catalog_stats');
        if (options.success) toast(options.success);
        return true;
      } catch (error) {
        fail(error);
        return false;
      }
    },
    [toast, fail],
  );
}

export const FILE_STATUS_LABELS: Record<string, string> = {
  not_provided: 'Não enviado', awaiting_upload: 'Aguardando envio ao cofre', received: 'Recebido (fora do cofre)', stored: 'Guardado no cofre',
};
export const PERMISSION_LABELS: Record<string, string> = {
  unknown: 'A confirmar', confirmed: 'Confirmada', restricted: 'Uso restrito', denied: 'Negada',
};

/** Converte "2026-11-01T03:00:00Z" ⇄ valor de <input type="datetime-local"> no fuso do navegador. */
export function toLocalInput(iso: string | null): string {
  if (!iso) return '';
  const date = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}
export const fromLocalInput = (value: string): string | null => (value ? new Date(value).toISOString() : null);
