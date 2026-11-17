-- Consolida a política de leitura da biblioteca e indexa a chave estrangeira do criador.
drop policy if exists "administradores gerenciam videos" on public.videos;
drop policy if exists "assinantes assistem videos publicados" on public.videos;
create policy "videos para administradores ou assinantes ativos" on public.videos
for select to authenticated
using ((select public.is_admin()) or (status = 'published' and (select public.has_active_access())));
create policy "administradores inserem videos" on public.videos
for insert to authenticated with check ((select public.is_admin()));
create policy "administradores atualizam videos" on public.videos
for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "administradores removem videos" on public.videos
for delete to authenticated using ((select public.is_admin()));
create index if not exists videos_created_by_idx on public.videos(created_by);
