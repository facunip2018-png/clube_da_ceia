import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { join } from 'node:path';
import { readFileSync } from 'node:fs';
import { TestDb } from './harness';

const migration = readFileSync(
  join(__dirname, '../../supabase/migrations/20261118132500_reconcile_rabanada_compatibilities.sql'),
  'utf8',
);

let db: TestDb;

beforeAll(async () => {
  db = await TestDb.create();
}, 60_000);

afterAll(async () => {
  await db.close();
});

describe('compatibilidades documentadas das rabanadas', () => {
  it('aponta os seis pares existentes para as massas reais e é idempotente', async () => {
    await db.sql(`
      insert into public.recipes (
        id, slug, collection_id, source_document_id, kind, component_role, flavor,
        title, original_language, translation_status, source_page_start, source_page_end,
        page_ref_verified, content_state, status, position
      )
      select gen_random_uuid(), 'massa-pao-rabanada-doce', collection_id, source_document_id,
             'component', 'base', 'doce', 'Massa de pão para rabanada doce',
             original_language, translation_status, 8, 8, true,
             'catalogued', 'draft', position + 100
      from public.recipes
      where slug = 'pao-para-rabanada-doce'
    `);

    await db.sql(`
      insert into public.recipes (
        id, slug, collection_id, source_document_id, kind, component_role, flavor,
        title, original_language, translation_status, source_page_start, source_page_end,
        page_ref_verified, content_state, status, position
      )
      select gen_random_uuid(), 'massa-pao-rabanada-salgada', collection_id, source_document_id,
             'component', 'base', 'salgado', 'Massa de pão para rabanada salgada',
             original_language, translation_status, 9, 9, true,
             'catalogued', 'draft', position + 100
      from public.recipes
      where slug = 'pao-para-rabanada-salgada'
    `);

    const before = await db.sql<{ n: number }>(`
      select count(*)::int as n
      from public.recipe_compatibilities compatibility
      join public.recipes base on base.id = compatibility.recipe_id
      join public.collections collection on collection.id = base.collection_id
      where collection.slug = 'rabanadas-recheadas'
    `);
    expect(before[0]?.n).toBe(6);

    await db.pg.exec(migration);

    const rows = await db.sql<{
      base_slug: string;
      filling_slug: string;
      source_page: number;
      verified: boolean;
      note: string;
    }>(`
      select base.slug as base_slug, filling.slug as filling_slug,
             compatibility.source_page, compatibility.verified, compatibility.note
      from public.recipe_compatibilities compatibility
      join public.recipes base on base.id = compatibility.recipe_id
      join public.recipes filling on filling.id = compatibility.compatible_recipe_id
      join public.collections collection on collection.id = base.collection_id
      where collection.slug = 'rabanadas-recheadas'
      order by compatibility.source_page
    `);

    expect(rows).toHaveLength(6);
    expect(rows.map((row) => [row.base_slug, row.filling_slug, row.source_page])).toEqual([
      ['massa-pao-rabanada-doce', 'rabanada-doce-recheada-com-nutella', 14],
      ['massa-pao-rabanada-doce', 'rabanada-doce-recheada-com-doce-de-leite', 15],
      ['massa-pao-rabanada-doce', 'rabanada-doce-com-brigadeiro-de-nozes', 16],
      ['massa-pao-rabanada-salgada', 'rabanada-salgada-com-gorgonzola-nozes-e-damasco', 18],
      ['massa-pao-rabanada-salgada', 'rabanada-salgada-com-salame-e-ricota', 20],
      ['massa-pao-rabanada-salgada', 'rabanada-salgada-com-peito-de-peru-e-queijo', 22],
    ]);
    expect(rows.every((row) => row.verified && row.note.includes('conferida'))).toBe(true);

    await db.pg.exec(migration);
    const after = await db.sql<{ n: number }>(`
      select count(*)::int as n
      from public.recipe_compatibilities compatibility
      join public.recipes base on base.id = compatibility.recipe_id
      join public.collections collection on collection.id = base.collection_id
      where collection.slug = 'rabanadas-recheadas'
    `);
    expect(after[0]?.n).toBe(6);
  });
});
