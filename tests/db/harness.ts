/**
 * Banco de testes: PostgreSQL real em WebAssembly (PGlite), sem Docker.
 * Reproduz o mínimo do ambiente Supabase (schemas auth/storage e roles da API)
 * para executar as migrations e a carga exatamente como serão executadas no projeto.
 */
import { PGlite } from '@electric-sql/pglite';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = join(__dirname, '..', '..');

const SUPABASE_SHIM = /* sql */ `
  create role anon nologin;
  create role authenticated nologin;
  create role service_role nologin bypassrls;

  create schema auth;
  create table auth.users (
    id uuid primary key default gen_random_uuid(),
    email text unique,
    raw_user_meta_data jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
  );
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', '')::uuid
  $$;
  create function auth.jwt() returns jsonb language sql stable as $$
    select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb)
  $$;
  grant usage on schema auth to anon, authenticated, service_role;
  grant execute on function auth.uid(), auth.jwt() to anon, authenticated, service_role;

  create schema storage;
  create table storage.buckets (
    id text primary key,
    name text not null,
    public boolean not null default false,
    file_size_limit bigint,
    allowed_mime_types text[],
    created_at timestamptz not null default now()
  );
  create table storage.objects (
    id uuid primary key default gen_random_uuid(),
    bucket_id text references storage.buckets (id),
    name text not null,
    owner uuid,
    created_at timestamptz not null default now(),
    unique (bucket_id, name)
  );
  alter table storage.objects enable row level security;
  create function storage.foldername(name text) returns text[] language sql immutable as $$
    select (string_to_array(name, '/'))[1 : array_length(string_to_array(name, '/'), 1) - 1]
  $$;
  grant usage on schema storage to anon, authenticated, service_role;
  grant select, insert, update, delete on storage.objects to authenticated, service_role;
  grant select on storage.buckets to authenticated, service_role;
  grant execute on function storage.foldername(text) to anon, authenticated, service_role;
`;

export type Role = 'anon' | 'authenticated' | 'service_role';

export class TestDb {
  constructor(public pg: PGlite) {}

  static async create({ seed = true }: { seed?: boolean } = {}): Promise<TestDb> {
    const pg = new PGlite();
    await pg.exec(SUPABASE_SHIM);
    const dir = join(ROOT, 'supabase', 'migrations');
    for (const file of readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()) {
      try {
        await pg.exec(readFileSync(join(dir, file), 'utf8'));
      } catch (error) {
        throw new Error(`Falha na migration ${file}: ${(error as Error).message}`);
      }
    }
    const db = new TestDb(pg);
    if (seed) await db.seed();
    return db;
  }

  /** Banco criado pelo arquivo único (o mesmo que pode ser colado no SQL Editor do Supabase). */
  static async fromSetupFile(): Promise<TestDb> {
    const pg = new PGlite();
    await pg.exec(SUPABASE_SHIM);
    await pg.exec(readFileSync(join(ROOT, 'supabase', 'setup_completo.sql'), 'utf8'));
    return new TestDb(pg);
  }

  async seed() {
    await this.pg.exec(readFileSync(join(ROOT, 'supabase', 'seed.sql'), 'utf8'));
  }

  /** Consulta como superusuário (equivalente ao SQL Editor). */
  async sql<T = Record<string, unknown>>(query: string, params: unknown[] = []): Promise<T[]> {
    const result = await this.pg.query<T>(query, params);
    return result.rows;
  }

  /** Executa como uma role da API, com o JWT de um usuário (ou sem usuário). */
  async as<T>(role: Role, userId: string | null, fn: (q: <R = Record<string, unknown>>(query: string, params?: unknown[]) => Promise<R[]>) => Promise<T>): Promise<T> {
    const claims = JSON.stringify({ role, ...(userId ? { sub: userId } : {}) });
    await this.pg.query(`select set_config('request.jwt.claims', $1, false)`, [claims]);
    await this.pg.exec(`set role ${role}`);
    try {
      return await fn(async (query, params = []) => (await this.pg.query(query, params)).rows as never);
    } finally {
      await this.pg.exec(`reset role`);
      await this.pg.query(`select set_config('request.jwt.claims', '', false)`);
    }
  }

  /** Cria um usuário como o Supabase Auth faria (dispara o gatilho de perfil). */
  async createUser(email: string, { admin = false, fullName = '' }: { admin?: boolean; fullName?: string } = {}): Promise<string> {
    const [row] = await this.sql<{ id: string }>(
      `insert into auth.users (email, raw_user_meta_data) values ($1, $2) returning id`,
      [email, JSON.stringify({ full_name: fullName })],
    );
    if (admin) await this.sql(`update public.profiles set role = 'admin' where id = $1`, [row.id]);
    return row.id;
  }

  async close() {
    await this.pg.close();
  }
}

/** Captura a mensagem de erro de uma consulta que deve falhar. */
export async function errorOf(promise: Promise<unknown>): Promise<string> {
  try {
    await promise;
  } catch (error) {
    return (error as Error).message;
  }
  return '';
}
