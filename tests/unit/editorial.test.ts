import { describe, expect, it } from 'vitest';
import { AppError, checkRecipeTransition, statusActions } from '@/lib/editorial';
import { pave } from './fixtures';

const recipe = () => ({
  ...pave().recipe,
  status: 'review' as const,
  content_state: 'structured' as const,
  reviewed_at: null,
  reviewed_by: null,
});

const context = (over: Partial<Parameters<typeof checkRecipeTransition>[2]> = {}) => ({
  openFlags: 0,
  permission: 'confirmed',
  linkedUnpublished: 0,
  userId: 'admin-test',
  now: '2026-11-17T12:00:00.000Z',
  ...over,
});

function codeOf(run: () => unknown): string | null {
  try {
    run();
    return null;
  } catch (error) {
    return error instanceof AppError ? error.code : 'UNKNOWN';
  }
}

describe('fluxo editorial', () => {
  it('não aprova ficha sem estrutura ou com pontos bloqueadores abertos', () => {
    expect(codeOf(() => checkRecipeTransition({ ...recipe(), content_state: 'catalogued' }, 'approved', context()))).toBe('CONTENT_REQUIRED');
    expect(codeOf(() => checkRecipeTransition(recipe(), 'approved', context({ openFlags: 1 })))).toBe('FLAGS_PENDING');
  });

  it('não publica sem aprovação, permissão confirmada ou componentes publicados', () => {
    expect(codeOf(() => checkRecipeTransition(recipe(), 'published', context()))).toBe('APPROVAL_REQUIRED');
    const approved = { ...recipe(), status: 'approved' as const, reviewed_at: context().now };
    expect(codeOf(() => checkRecipeTransition(approved, 'published', context({ permission: 'unknown' })))).toBe('PERMISSION_REQUIRED');
    expect(codeOf(() => checkRecipeTransition(approved, 'published', context({ linkedUnpublished: 1 })))).toBe('LINKED_COMPONENT_UNPUBLISHED');
  });

  it('publica somente uma ficha aprovada, revisada e autorizada', () => {
    const approved = { ...recipe(), status: 'approved' as const, reviewed_at: context().now };
    expect(checkRecipeTransition(approved, 'published', context())).toMatchObject({
      status: 'published',
      published_at: context().now,
    });
  });

  it('separa aprovação e publicação nas ações administrativas', () => {
    expect(statusActions('draft').map((action) => action.to)).toEqual(['approved', 'archived']);
    expect(statusActions('review').map((action) => action.to)).toEqual(['approved', 'archived']);
    expect(statusActions('approved').map((action) => action.to)).toEqual(['published', 'review', 'archived']);
    expect(statusActions('published').map((action) => action.to)).toEqual(['review', 'archived']);
    expect(statusActions('archived').map((action) => action.to)).toEqual(['review']);
    expect(statusActions('pending_permission')).toEqual([]);
  });

  it('retornar à revisão remove a aprovação anterior', () => {
    const approved = { ...recipe(), status: 'approved' as const, reviewed_at: context().now, reviewed_by: 'admin-test' };
    expect(checkRecipeTransition(approved, 'review', context())).toMatchObject({
      status: 'review',
      reviewed_at: null,
      reviewed_by: null,
    });
  });
});
