create table if not exists public.document_extracted_pages (
  source_document_id uuid not null references public.source_documents(id) on delete cascade,
  page_number integer not null check (page_number > 0),
  page_text text not null default '',
  extracted_at timestamptz not null default now(),
  primary key (source_document_id, page_number)
);

alter table public.document_extracted_pages enable row level security;
revoke all on public.document_extracted_pages from anon, authenticated;
grant select, insert, update, delete on public.document_extracted_pages to authenticated;
grant all on public.document_extracted_pages to service_role;

create policy "administradores acessam texto extraido dos PDFs"
  on public.document_extracted_pages
  for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

comment on table public.document_extracted_pages is
  'Texto extraído localmente dos PDFs privados para revisão e cadastro administrativo, sem uso de serviços de IA.';
