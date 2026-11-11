/**
 * Conferência do banco hospedado (Supabase) contra as migrations e a carga deste repositório.
 *
 *   npm run db:conferir
 *
 * Monta o banco de referência em memória (PGlite) a partir de supabase/migrations + supabase/seed.sql,
 * calcula as "impressões digitais" esperadas e grava supabase/.temp/conferencia.sql.
 * Cole esse arquivo no SQL Editor do Supabase: cada linha do resultado deve vir com ok = true.
 *
 *   • dados:*       conteúdo carregado pela seed (só bate enquanto ninguém editou pelo painel)
 *   • estrutura:*   funções, gatilhos, policies e buckets
 *   • permissoes:*  o que as roles da API (anon/authenticated/service_role) conseguem fazer
 *
 * Fora do `npm run db:conferir` este arquivo é ignorado pela suíte.
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { TestDb } from './harness';

const ENABLED = process.env.npm_lifecycle_event === 'db:conferir' || process.env.CONFERENCIA === '1';

/** Tabelas preenchidas pela seed. */
const SEED_TABLES = [
  'seasons', 'collections', 'source_documents', 'ingredients', 'challenges', 'recipes', 'recipe_components',
  'recipe_ingredients', 'recipe_steps', 'recipe_step_ingredients', 'recipe_step_timers', 'recipe_notes',
  'recipe_tags', 'recipe_compatibilities', 'review_flags',
];

const rowHash = `md5((to_jsonb(x) - 'created_at' - 'updated_at')::text)`;

/** Cada verificação é uma subconsulta que devolve UM texto. */
const CHECKS: Record<string, string> = {
  ...Object.fromEntries(
    SEED_TABLES.map((t) => [
      `dados:${t}`,
      `select count(*) || ' linhas · ' || md5(coalesce(string_agg(${rowHash}, '' order by x.id), '')) from public.${t} x`,
    ]),
  ),

  'estrutura:tabelas_sem_rls': `select count(*)::text from pg_tables where schemaname = 'public' and not rowsecurity`,

  'estrutura:colunas': `
    select count(*) || ' colunas · ' || md5(string_agg(c.table_name || '.' || c.column_name || ':' || c.data_type || ':' || c.is_nullable || ':' || coalesce(c.column_default, ''), '|' order by c.table_name, c.ordinal_position))
    from information_schema.columns c where c.table_schema = 'public'`,

  'estrutura:restricoes': `
    select count(*) || ' restrições · ' || md5(string_agg(c.conrelid::regclass::text || ':' || c.conname || ':' || pg_get_constraintdef(c.oid), '|' order by c.conrelid::regclass::text, c.conname))
    from pg_constraint c
    -- contype 'n' (NOT NULL) só existe no catálogo a partir do PostgreSQL 18; já é coberto por estrutura:colunas
    where c.connamespace = 'public'::regnamespace and c.contype <> 'n'`,

  'estrutura:indices': `
    select count(*) || ' índices · ' || md5(string_agg(i.indexdef, '|' order by i.tablename, i.indexname))
    from pg_indexes i where i.schemaname = 'public'`,

  'estrutura:funcoes': `
    select count(*) || ' funções · ' || md5(string_agg(
      p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' || ':' || p.prosecdef::int || ':' || coalesce(array_to_string(p.proconfig, ','), '') || ':' || md5(p.prosrc),
      '|' order by p.proname, pg_get_function_identity_arguments(p.oid)))
    from pg_proc p where p.pronamespace = 'public'::regnamespace`,

  'estrutura:gatilhos': `
    select count(*) || ' gatilhos · ' || md5(string_agg(c.relname || ':' || t.tgname || ':' || t.tgtype || ':' || p.proname, '|' order by c.relname, t.tgname))
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_proc p on p.oid = t.tgfoid
    where c.relnamespace = 'public'::regnamespace and not t.tgisinternal`,

  'estrutura:gatilhos_auth_users': `
    select coalesce(string_agg(t.tgname || '→' || p.proname, ', ' order by t.tgname), '')
    from pg_trigger t join pg_proc p on p.oid = t.tgfoid
    where t.tgrelid = 'auth.users'::regclass and not t.tgisinternal`,

  'estrutura:policies_public': `
    select count(*) || ' policies · ' || md5(string_agg(tablename || ':' || policyname || ':' || cmd || ':' || array_to_string(roles, ',') || ':' || coalesce(qual, '') || ':' || coalesce(with_check, ''), '|' order by tablename, policyname))
    from pg_policies where schemaname = 'public'`,

  'estrutura:policies_storage': `
    select count(*) || ' policies · ' || md5(string_agg(tablename || ':' || policyname || ':' || cmd || ':' || array_to_string(roles, ',') || ':' || coalesce(qual, '') || ':' || coalesce(with_check, ''), '|' order by tablename, policyname))
    from pg_policies where schemaname = 'storage'`,

  'estrutura:buckets': `
    select coalesce(string_agg(id || (case when public then ' (público' else ' (privado' end) || ', ' || coalesce(file_size_limit::text, 'sem limite') || ' bytes, ' || coalesce(array_to_string(allowed_mime_types, '+'), 'qualquer tipo') || ')', ' · ' order by id), '')
    from storage.buckets`,

  // O que cada role da API consegue fazer em cada tabela/visão (inclui permissões herdadas de PUBLIC).
  'permissoes:tabelas': `
    select md5(string_agg(r.role || ':' || c.relname || ':' ||
      has_table_privilege(r.role, c.oid, 'select')::int || has_table_privilege(r.role, c.oid, 'insert')::int ||
      has_table_privilege(r.role, c.oid, 'update')::int || has_table_privilege(r.role, c.oid, 'delete')::int ||
      has_table_privilege(r.role, c.oid, 'truncate')::int || has_table_privilege(r.role, c.oid, 'references')::int ||
      has_table_privilege(r.role, c.oid, 'trigger')::int, '|' order by r.role, c.relname))
    from pg_class c cross join (values ('anon'), ('authenticated')) r(role)
    where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v')`,

  'permissoes:colunas': `
    select md5(string_agg(r.role || ':' || c.relname || '.' || a.attname || ':' ||
      has_column_privilege(r.role, c.oid, a.attnum, 'select')::int || has_column_privilege(r.role, c.oid, a.attnum, 'insert')::int ||
      has_column_privilege(r.role, c.oid, a.attnum, 'update')::int, '|' order by r.role, c.relname, a.attname))
    from pg_class c
    join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
    cross join (values ('anon'), ('authenticated')) r(role)
    where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v')`,

  'permissoes:funcoes': `
    select coalesce(string_agg(p.proname || '=' ||
      (case when has_function_privilege('anon', p.oid, 'execute') then 'anon+' else '' end) ||
      (case when has_function_privilege('authenticated', p.oid, 'execute') then 'authenticated+' else '' end) ||
      (case when has_function_privilege('service_role', p.oid, 'execute') then 'service_role' else '' end), ' · ' order by p.proname), '')
    from pg_proc p where p.pronamespace = 'public'::regnamespace`,
};

const sqlText = (value: string) => `'${value.replace(/'/g, "''")}'`;
const oneLine = (sql: string) => sql.replace(/\s+/g, ' ').trim();

describe.skipIf(!ENABLED)('conferência do banco hospedado', () => {
  it('gera supabase/.temp/conferencia.sql com os valores esperados', async () => {
    const db = await TestDb.create();
    try {
      await db.pg.exec(`set time zone 'UTC'`);
      const expected: Record<string, string> = {};
      for (const [name, query] of Object.entries(CHECKS)) {
        const [row] = await db.sql<{ v: string | null }>(`select (${query}) as v`);
        expected[name] = row.v ?? '';
      }

      const rows = Object.entries(CHECKS)
        .map(([name, query]) => `  select ${sqlText(name)}, ${sqlText(expected[name])}, (${oneLine(query)})`)
        .join('\n  union all\n');

      const file = [
        '-- Conferência do banco hospedado — GERADO por `npm run db:conferir`. Não versionar.',
        '-- Cole no SQL Editor do Supabase. Todas as linhas devem vir com ok = true.',
        '-- (as linhas "dados:*" deixam de bater, legitimamente, depois de edições feitas pelo painel)',
        `set time zone 'UTC';`,
        'with checks (verificacao, esperado, encontrado) as (',
        rows,
        ')',
        `select verificacao, coalesce(esperado = encontrado, false) as ok,`,
        `  case when esperado = encontrado then '' else 'esperado: ' || esperado || ' | encontrado: ' || coalesce(encontrado, '(nulo)') end as detalhe`,
        'from checks order by 2, 1;',
        '',
      ].join('\n');

      const dir = join(__dirname, '..', '..', 'supabase', '.temp');
      mkdirSync(dir, { recursive: true });
      writeFileSync(join(dir, 'conferencia.sql'), file);
      writeFileSync(join(dir, 'conferencia.esperado.json'), JSON.stringify(expected, null, 2) + '\n');

      expect(expected['estrutura:tabelas_sem_rls']).toBe('0');
      expect(Object.keys(expected).length).toBe(Object.keys(CHECKS).length);
    } finally {
      await db.close();
    }
  });
});
