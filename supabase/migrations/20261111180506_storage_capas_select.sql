-- =====================================================================
-- Clube da Ceia Perfeita — 05. Storage: capas (ajuste)
-- A API do Storage precisa de SELECT para listar, substituir (upsert) e
-- remover arquivos. Sem esta policy, administradores conseguiam enviar
-- capas para recipe-images, mas não removê-las nem substituí-las
-- (encontrado no teste contra o projeto hospedado: tests/hosted/smoke.mjs).
-- A leitura pública das capas continua sendo feita pela URL pública do bucket.
-- =====================================================================

create policy "capas: administradores listam"
  on storage.objects for select to authenticated
  using (bucket_id = 'recipe-images' and (select public.is_admin()));
