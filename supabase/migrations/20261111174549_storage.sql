-- =====================================================================
-- Clube da Ceia Perfeita — 04. Storage
--   source-documents  (privado)  PDFs originais dos e-books — somente administradores
--   challenge-photos  (privado)  fotos enviadas nos desafios — cada pessoa na própria pasta
--   recipe-images     (público)  capas de receitas e coleções enviadas pelo admin
-- =====================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('source-documents', 'source-documents', false, 52428800, array['application/pdf'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('challenge-photos', 'challenge-photos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('recipe-images', 'recipe-images', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- PDFs originais: nunca públicos. Leitura e escrita apenas para administradores.
create policy "pdfs originais: somente administradores"
  on storage.objects for all to authenticated
  using (bucket_id = 'source-documents' and (select public.is_admin()))
  with check (bucket_id = 'source-documents' and (select public.is_admin()));

-- Fotos dos desafios: cada pessoa lê, envia e apaga dentro de <user_id>/…
create policy "fotos de desafios: pasta propria (leitura)"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'challenge-photos'
    and ((storage.foldername(name))[1] = (select auth.uid())::text or (select public.is_admin()))
  );

create policy "fotos de desafios: pasta propria (envio)"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'challenge-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "fotos de desafios: pasta propria (remocao)"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'challenge-photos'
    and ((storage.foldername(name))[1] = (select auth.uid())::text or (select public.is_admin()))
  );

-- Capas: leitura pública pelo próprio bucket; escrita apenas para administradores.
create policy "capas: administradores enviam"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'recipe-images' and (select public.is_admin()));

create policy "capas: administradores atualizam"
  on storage.objects for update to authenticated
  using (bucket_id = 'recipe-images' and (select public.is_admin()))
  with check (bucket_id = 'recipe-images' and (select public.is_admin()));

create policy "capas: administradores removem"
  on storage.objects for delete to authenticated
  using (bucket_id = 'recipe-images' and (select public.is_admin()));
