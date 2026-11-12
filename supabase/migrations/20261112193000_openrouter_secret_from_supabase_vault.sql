create or replace function public.admin_get_openrouter_key()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  secret_value text;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Acesso negado';
  end if;

  select decrypted_secret
    into secret_value
    from vault.decrypted_secrets
   where name = 'openrouter_api_key'
   limit 1;

  return secret_value;
end;
$$;

revoke all on function public.admin_get_openrouter_key() from public;
revoke all on function public.admin_get_openrouter_key() from anon;
grant execute on function public.admin_get_openrouter_key() to authenticated;
