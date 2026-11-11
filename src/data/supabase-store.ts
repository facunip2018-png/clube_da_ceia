import type { SupabaseClient } from '@supabase/supabase-js';
import type { TableName, Tables } from '@/lib/types';
import { toAppError } from '@/lib/editorial';
import type { DataStore, Query, Rpc, RpcName } from './store';

/** Acesso ao Supabase com a sessão da pessoa: quem decide o que ela pode ver é o RLS do banco. */
export class SupabaseStore implements DataStore {
  readonly kind = 'supabase' as const;
  constructor(private client: SupabaseClient) {}

  async list<K extends TableName>(table: K, query: Query<Tables[K]> = {}): Promise<Tables[K][]> {
    let q = this.client.from(table).select('*');
    for (const [column, value] of Object.entries(query.eq ?? {})) {
      q = value === null ? q.is(column, null) : q.eq(column, value as string | number | boolean);
    }
    for (const [column, values] of Object.entries(query.in ?? {})) {
      q = q.in(column, values as (string | number)[]);
    }
    for (const [column, direction] of query.order ?? []) {
      q = q.order(column, { ascending: direction === 'asc' });
    }
    if (query.limit) q = q.limit(query.limit);
    const { data, error } = await q;
    if (error) throw toAppError(error);
    return (data ?? []) as Tables[K][];
  }

  async insert<K extends TableName>(table: K, values: Partial<Tables[K]> | Partial<Tables[K]>[]): Promise<Tables[K][]> {
    // defaultToNull: false → em inserções em lote, coluna ausente em uma linha usa o DEFAULT do banco
    // (o padrão do PostgREST é gravar NULL, o que viola colunas NOT NULL com valor padrão).
    const { data, error } = await this.client.from(table).insert(values as never, { defaultToNull: false }).select();
    if (error) throw toAppError(error);
    return (data ?? []) as Tables[K][];
  }

  async update<K extends TableName>(table: K, match: NonNullable<Query<Tables[K]>['eq']>, patch: Partial<Tables[K]>): Promise<Tables[K][]> {
    const { data, error } = await this.client.from(table).update(patch as never).match(match as Record<string, unknown>).select();
    if (error) throw toAppError(error);
    return (data ?? []) as Tables[K][];
  }

  async remove<K extends TableName>(table: K, match: NonNullable<Query<Tables[K]>['eq']>): Promise<void> {
    const { error } = await this.client.from(table).delete().match(match as Record<string, unknown>);
    if (error) throw toAppError(error);
  }

  async rpc<N extends RpcName>(name: N, args?: Rpc[N]['args']): Promise<Rpc[N]['result']> {
    const { data, error } = await this.client.rpc(name, args as never);
    if (error) throw toAppError(error);
    return data as Rpc[N]['result'];
  }
}
