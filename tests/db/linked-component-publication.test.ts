import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { TestDb, errorOf } from './harness';

describe('proteção editorial de fichas compostas por componentes vinculados', () => {
  let db: TestDb;
  let admin: string;
  let sourceDocumentId: string;
  let collectionId: string;

  beforeAll(async () => {
    db = await TestDb.create();
    admin = await db.createUser('linked-components-admin@clube.test', { admin: true });
    const [source] = await db.sql<{ id: string; collection_id: string }>(`
      select id, collection_id
      from public.source_documents
      where collection_id is not null
      order by created_at
      limit 1
    `);
    sourceDocumentId = source.id;
    collectionId = source.collection_id;
    await db.sql(`
      update public.source_documents
      set commercial_permission = 'confirmed',
          permission_notes = 'Permissão simulada exclusivamente no banco isolado de testes'
      where id = $1
    `, [sourceDocumentId]);
  }, 60_000);

  afterAll(async () => {
    await db.close();
  });

  it('considera ingredientes e etapas vinculados e bloqueia alertas nos componentes', async () => {
    const insertRecipe = async (
      slug: string,
      title: string,
      kind: 'component' | 'variation',
      componentRole: 'base' | 'recheio' | null,
    ) => {
      const [row] = await db.sql<{ id: string }>(`
        insert into public.recipes (
          slug, collection_id, source_document_id, kind, component_role,
          title, original_language, translation_status, content_state, status, position
        )
        values ($1, $2, $3, $4, $5, $6, 'pt-BR', 'not_needed', 'structured', 'draft',
          coalesce((select max(position) + 1 from public.recipes where collection_id = $2), 0))
        returning id
      `, [slug, collectionId, sourceDocumentId, kind, componentRole, title]);
      return row.id;
    };

    const baseId = await insertRecipe('test-linked-base', 'Base vinculada de teste', 'component', 'base');
    const fillingId = await insertRecipe('test-linked-filling', 'Recheio vinculado de teste', 'component', 'recheio');
    const variationId = await insertRecipe('test-linked-variation', 'Variação composta de teste', 'variation', null);

    for (const [recipeId, slug, name] of [
      [baseId, 'test-linked-base-ingredient', 'Ingrediente da base'],
      [fillingId, 'test-linked-filling-ingredient', 'Ingrediente do recheio'],
    ] as const) {
      const [ingredient] = await db.sql<{ id: string }>(`
        insert into public.ingredients (slug, name) values ($1, $2) returning id
      `, [slug, name]);
      await db.sql(`
        insert into public.recipe_ingredients (
          recipe_id, ingredient_id, position, display_name, original_text
        ) values ($1, $2, 1, $3, $3)
      `, [recipeId, ingredient.id, name]);
      await db.sql(`
        insert into public.recipe_steps (recipe_id, position, instruction, original_text)
        values ($1, 1, $2, $2)
      `, [recipeId, 'Preparo de teste para ' + name.toLowerCase()]);
    }

    await db.sql(`
      insert into public.recipe_components (recipe_id, linked_recipe_id, role, title, position)
      values
        ($1, $2, 'base', 'Base', 0),
        ($1, $3, 'recheio', 'Recheio', 1)
    `, [variationId, baseId, fillingId]);

    const [direct] = await db.sql<{ ingredients: number; steps: number }>(`
      select
        (select count(*)::int from public.recipe_ingredients where recipe_id = $1) as ingredients,
        (select count(*)::int from public.recipe_steps where recipe_id = $1) as steps
    `, [variationId]);
    expect(direct).toEqual({ ingredients: 0, steps: 0 });

    const [linked] = await db.sql<{ ingredients: number; steps: number }>(`
      select
        (select count(*)::int from public.recipe_ingredients i
          where i.recipe_id in ($1, $2)) as ingredients,
        (select count(*)::int from public.recipe_steps s
          where s.recipe_id in ($1, $2)) as steps
    `, [baseId, fillingId]);
    expect(linked).toEqual({ ingredients: 2, steps: 2 });

    await db.sql(`
      insert into public.review_flags (recipe_id, source_document_id, entity, field, severity, message)
      values ($1, $2, 'component', 'source', 'warning', 'Pendência de componente criada no teste')
    `, [baseId, sourceDocumentId]);

    await db.as('authenticated', admin, async (q) => {
      const blockedByLinkedFlag = await errorOf(
        q(`update public.recipes set status = 'approved' where id = $1`, [variationId]),
      );
      expect(blockedByLinkedFlag).toContain('FLAGS_PENDING');

      await q(`
        update public.review_flags
        set resolved_at = now(), resolved_by = $1, resolution_note = 'Resolvido no teste'
        where recipe_id = $2 and resolved_at is null
      `, [admin, baseId]);

      for (const componentId of [baseId, fillingId]) {
        await q(`update public.recipes set status = 'approved' where id = $1`, [componentId]);
        await q(`update public.recipes set status = 'published' where id = $1`, [componentId]);
      }

      await q(`update public.recipes set status = 'approved' where id = $1`, [variationId]);
      await q(`update public.recipes set status = 'published' where id = $1`, [variationId]);
    });

    const [published] = await db.sql<{ status: string; reviewed_at: string | null; published_at: string | null }>(`
      select status, reviewed_at, published_at
      from public.recipes where id = $1
    `, [variationId]);
    expect(published.status).toBe('published');
    expect(published.reviewed_at).toBeTruthy();
    expect(published.published_at).toBeTruthy();
  });
});
