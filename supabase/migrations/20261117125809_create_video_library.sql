-- Biblioteca de vídeos Gumlet do Clube da Ceia Perfeita.
-- Vídeos publicados são visíveis somente para assinantes com acesso ativo; CRUD é exclusivo de administradores.
begin;
create table if not exists public.videos (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title text not null check (char_length(btrim(title)) between 2 and 160),
  description text,
  hls_url text,
  mp4_url text,
  thumbnail_url text,
  duration_seconds integer check (duration_seconds is null or duration_seconds > 0),
  collection_id uuid references public.collections(id) on delete set null,
  recipe_id uuid references public.recipes(id) on delete set null,
  status text not null default 'draft' check (status in ('draft', 'published', 'archived')),
  position integer not null default 0,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint videos_has_source check (hls_url is not null or mp4_url is not null),
  constraint videos_hls_https check (hls_url is null or hls_url ~* '^https://'),
  constraint videos_mp4_https check (mp4_url is null or mp4_url ~* '^https://'),
  constraint videos_thumbnail_https check (thumbnail_url is null or thumbnail_url ~* '^https://')
);
create index if not exists videos_status_position_idx on public.videos(status, position);
create index if not exists videos_collection_idx on public.videos(collection_id);
create index if not exists videos_recipe_idx on public.videos(recipe_id);
drop trigger if exists set_updated_at on public.videos;
create trigger set_updated_at before update on public.videos
  for each row execute function public.set_updated_at();
alter table public.videos enable row level security;
revoke all on public.videos from anon, authenticated;
grant select, insert, update, delete on public.videos to authenticated;
drop policy if exists "administradores gerenciam videos" on public.videos;
create policy "administradores gerenciam videos" on public.videos
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
drop policy if exists "assinantes assistem videos publicados" on public.videos;
create policy "assinantes assistem videos publicados" on public.videos
  for select to authenticated using (status = 'published' and (select public.has_active_access()));
insert into public.videos (slug, title, description, hls_url, status, position)
values ('video-gumlet-demo','Vídeo de demonstração Gumlet','Vídeo inicial fornecido para configurar e testar o player. Revise o título e publique quando estiver pronto.','https://video.gumlet.io/6ad7bb851ab4445ed4e7f416/6ad7c30a1ab4445ed4e82f97/main.m3u8','draft',1)
on conflict (slug) do nothing;
commit;
