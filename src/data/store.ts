/**
 * Contrato único de acesso a dados. As telas não sabem se estão falando com o
 * Supabase (produção) ou com o armazenamento local (modo demonstração).
 */
import type { Access, CatalogStat, TableName, Tables, UserChallenge } from '@/lib/types';

type Scalar = string | number | boolean | null;

export interface Query<T> {
  eq?: { [K in keyof T]?: Scalar };
  in?: { [K in keyof T]?: (string | number)[] };
  order?: [keyof T & string, 'asc' | 'desc'][];
  limit?: number;
}

export interface Rpc {
  my_access: { args: undefined; result: Access };
  catalog_stats: { args: undefined; result: CatalogStat[] };
  refresh_my_challenges: { args: undefined; result: UserChallenge[] };
  admin_usage_stats: { args: undefined; result: Record<string, unknown> };
  admin_set_role: { args: { p_user: string; p_role: 'customer' | 'admin' }; result: null };
}
export type RpcName = keyof Rpc;

export interface DataStore {
  readonly kind: 'supabase' | 'demo';
  list<K extends TableName>(table: K, query?: Query<Tables[K]>): Promise<Tables[K][]>;
  insert<K extends TableName>(table: K, values: Partial<Tables[K]> | Partial<Tables[K]>[]): Promise<Tables[K][]>;
  update<K extends TableName>(table: K, match: NonNullable<Query<Tables[K]>['eq']>, patch: Partial<Tables[K]>): Promise<Tables[K][]>;
  remove<K extends TableName>(table: K, match: NonNullable<Query<Tables[K]>['eq']>): Promise<void>;
  rpc<N extends RpcName>(name: N, args?: Rpc[N]['args']): Promise<Rpc[N]['result']>;
}
