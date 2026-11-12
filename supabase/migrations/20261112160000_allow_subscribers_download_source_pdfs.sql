create or replace view public.source_document_refs as
select
  d.id,
  d.title,
  d.author,
  d.publisher,
  d.language,
  d.file_name,
  d.storage_path
from public.source_documents d
where exists (
  select 1
  from public.recipes r
  where r.source_document_id = d.id
    and r.status = 'published'
);

grant select on public.source_document_refs to anon, authenticated;

drop policy if exists "pdfs originais: assinantes e administradores baixam" on storage.objects;
create policy "pdfs originais: assinantes e administradores baixam"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'source-documents'
  and coalesce((select public.my_access() ->> 'has_access'), 'false') = 'true'
);