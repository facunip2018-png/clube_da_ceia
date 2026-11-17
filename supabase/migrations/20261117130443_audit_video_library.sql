-- Registra no histórico administrativo inclusões, alterações e arquivamentos da biblioteca de vídeos.
create or replace function public.audit_video_changes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.write_audit_log('videos.created', 'videos', new.id::text, new.title, null, to_jsonb(new));
    return new;
  elsif tg_op = 'UPDATE' then
    perform public.write_audit_log('videos.updated', 'videos', new.id::text, new.title, to_jsonb(old), to_jsonb(new));
    return new;
  elsif tg_op = 'DELETE' then
    perform public.write_audit_log('videos.deleted', 'videos', old.id::text, old.title, to_jsonb(old), null);
    return old;
  end if;
  return null;
end;
$$;
revoke all on function public.audit_video_changes() from public, anon, authenticated;
drop trigger if exists audit_video_changes on public.videos;
create trigger audit_video_changes after insert or update or delete on public.videos
for each row execute function public.audit_video_changes();
