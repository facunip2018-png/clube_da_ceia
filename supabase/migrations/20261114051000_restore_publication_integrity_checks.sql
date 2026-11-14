-- Reforça as condições de publicação sem alterar receitas já publicadas.
-- A publicação continua direta no painel, mas exige ficha estruturada, revisão sem
-- avisos/bloqueios pendentes, permissão comercial confirmada quando há fonte e
-- componentes vinculados já publicados.
begin;

create or replace function public.guard_recipe_status()
returns trigger
language plpgsql
set search_path = public
as $function$
declare
  v_permission text;
begin
  if tg_op = 'INSERT' or old.status is distinct from new.status then
    if new.status in ('approved', 'published') then
      if new.content_state is distinct from 'structured' then
        raise exception 'CONTENT_REQUIRED';
      end if;

      if exists (
        select 1
        from public.review_flags
        where recipe_id = new.id
          and resolved_at is null
          and severity in ('warning', 'blocker')
      ) then
        raise exception 'FLAGS_PENDING';
      end if;
    end if;

    if new.status = 'approved' then
      new.reviewed_at := now();
      new.reviewed_by := coalesce(auth.uid(), new.reviewed_by);
    end if;

    if new.status = 'published' then
      if new.source_document_id is not null then
        select commercial_permission
          into v_permission
        from public.source_documents
        where id = new.source_document_id;

        if v_permission is distinct from 'confirmed' then
          raise exception 'PERMISSION_REQUIRED';
        end if;
      end if;

      if exists (
        select 1
        from public.recipe_components component
        join public.recipes linked_recipe on linked_recipe.id = component.linked_recipe_id
        where component.recipe_id = new.id
          and component.linked_recipe_id is not null
          and linked_recipe.status <> 'published'
      ) then
        raise exception 'LINKED_COMPONENT_UNPUBLISHED';
      end if;

      new.published_at := coalesce(new.published_at, now());
    end if;
  end if;

  return new;
end;
$function$;

commit;
