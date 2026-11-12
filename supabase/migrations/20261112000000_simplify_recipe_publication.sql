-- Publicação direta de receitas completas.
-- A liberação não depende mais de aprovação, flags editoriais ou conferência manual.
-- Mantém apenas a proteção para não publicar fichas sem ingredientes e etapas.
create or replace function public.guard_recipe_status()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if new.status = 'published' and new.content_state <> 'structured' then
    raise exception 'CONTENT_REQUIRED: a receita precisa ter ingredientes e modo de preparo cadastrados.' using errcode = 'P0001';
  end if;

  if new.status = 'published' and new.published_at is null then
    new.published_at := now();
  end if;

  return new;
end
$function$;

-- Libera imediatamente as fichas já estruturadas no catálogo.
update public.recipes
set status = 'published',
    published_at = coalesce(published_at, now()),
    updated_at = now()
where content_state = 'structured'
  and kind = 'recipe'
  and status <> 'published'
  and exists (select 1 from public.recipe_ingredients i where i.recipe_id = recipes.id)
  and exists (select 1 from public.recipe_steps s where s.recipe_id = recipes.id);
