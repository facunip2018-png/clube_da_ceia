-- Materiais de apoio compartilhados: utensílios, ingredientes básicos, dicas e orientações.
create table if not exists public.support_materials (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  kind text not null check (kind in ('utensilios', 'ingredientes', 'dicas', 'orientacoes')),
  title text not null,
  body text not null,
  source_document_id uuid references public.source_documents(id) on delete set null,
  source_page integer check (source_page is null or source_page > 0),
  position integer not null default 0,
  is_visible boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists support_materials_kind_position_idx
  on public.support_materials (kind, position);

alter table public.support_materials enable row level security;

grant select, insert, update, delete on public.support_materials to authenticated;

create policy "materiais de apoio para assinantes" on public.support_materials
  for select to authenticated
  using (
    (select public.is_admin())
    or ((select public.has_active_access()) and is_visible)
  );

create policy "administradores gerenciam materiais de apoio" on public.support_materials
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create trigger set_updated_at
  before update on public.support_materials
  for each row execute function public.set_updated_at();

create trigger audit_row_change
  after insert or update or delete on public.support_materials
  for each row execute function public.audit_row_change();
