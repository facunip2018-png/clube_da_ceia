import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { TestDb } from './harness';

type ImportResult = {
  created: number;
  skipped: number;
  support_materials: number;
  published: boolean;
  pending_review: boolean;
  permission_confirmed: boolean;
};

describe('importação de PDF respeita revisão humana', () => {
  let db: TestDb;
  let adminId: string;
  let documentId: string;

  beforeAll(async () => {
    db = await TestDb.create();
    adminId = await db.createUser('pdf-import-review-admin@clube.test', { admin: true });
    const [document] = await db.sql<{ id: string }>(`
      select id
      from public.source_documents
      where collection_id is not null
      order by created_at
      limit 1
    `);
    documentId = document.id;
    await db.sql(`
      update public.source_documents
      set file_status = 'stored',
          storage_path = 'test-only/import-review.pdf',
          commercial_permission = 'confirmed',
          permission_notes = 'Simulação isolada do teste; não é autorização real'
      where id = $1
    `, [documentId]);
  }, 60_000);

  afterAll(async () => {
    await db.close();
  });

  it('importa uma ficha completa como revisão, não como publicação automática', async () => {
    const payload = {
      collection: {},
      recipes: [{
        title: 'Ficha de teste — aguarda aprovação humana',
        ingredients: [{ display_name: 'Ingrediente de teste', original_text: 'Ingrediente de teste' }],
        steps: [{ instruction: 'Etapa de teste.', original_text: 'Etapa de teste.' }],
      }],
      support_materials: [],
    };

    const [result] = await db.as('authenticated', adminId, (q) => q<{ result: ImportResult }>(`
      select public.admin_import_pdf_recipes($1::uuid, $2::jsonb) as result
    `, [documentId, JSON.stringify(payload)]));

    expect(result.result).toMatchObject({
      created: 1,
      skipped: 0,
      support_materials: 0,
      published: false,
      pending_review: true,
      permission_confirmed: true,
    });

    const [recipe] = await db.sql<{
      status: string;
      content_state: string;
      reviewed_at: string | null;
      published_at: string | null;
      ingredients: number;
      steps: number;
    }>(`
      select r.status, r.content_state, r.reviewed_at, r.published_at,
        (select count(*)::int from public.recipe_ingredients i where i.recipe_id = r.id) as ingredients,
        (select count(*)::int from public.recipe_steps s where s.recipe_id = r.id) as steps
      from public.recipes r
      where r.source_document_id = $1
        and r.title = 'Ficha de teste — aguarda aprovação humana'
    `, [documentId]);

    expect(recipe).toMatchObject({
      status: 'review',
      content_state: 'structured',
      reviewed_at: null,
      published_at: null,
      ingredients: 1,
      steps: 1,
    });
  });

  it('mantém a importação em pending_permission quando a fonte não tem permissão confirmada', async () => {
    await db.sql(`
      update public.source_documents
      set commercial_permission = 'restricted',
          permission_notes = 'Simulação isolada sem permissão'
      where id = $1
    `, [documentId]);

    const payload = {
      collection: {},
      recipes: [{
        title: 'Ficha de teste — permissão pendente',
        ingredients: [{ display_name: 'Ingrediente de teste', original_text: 'Ingrediente de teste' }],
        steps: [{ instruction: 'Etapa de teste.', original_text: 'Etapa de teste.' }],
      }],
      support_materials: [],
    };

    const [result] = await db.as('authenticated', adminId, (q) => q<{ result: ImportResult }>(`
      select public.admin_import_pdf_recipes($1::uuid, $2::jsonb) as result
    `, [documentId, JSON.stringify(payload)]));

    expect(result.result).toMatchObject({
      created: 1,
      skipped: 0,
      published: false,
      pending_review: false,
      permission_confirmed: false,
    });

    const [recipe] = await db.sql<{ status: string; reviewed_at: string | null; published_at: string | null }>(`
      select status, reviewed_at, published_at
      from public.recipes
      where source_document_id = $1
        and title = 'Ficha de teste — permissão pendente'
    `, [documentId]);

    expect(recipe).toEqual({ status: 'pending_permission', reviewed_at: null, published_at: null });
  });
});
