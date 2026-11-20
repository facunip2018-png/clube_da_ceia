-- Restaura a proteção editorial que foi removida pela migração
-- 20261112000000_simplify_recipe_publication.sql.
--
-- Para fichas compostas, ingredientes, etapas e alertas podem estar nas
-- receitas-componentes vinculadas, sem linhas diretas na receita principal.
-- Esta função considera ambos os formatos, sem alterar registros existentes.

create or replace function public.guard_recipe_status()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_permission text;
  v_status_changed boolean;
begin
  if tg_op = 'INSERT' then
    v_status_changed := true;
  else
    v_status_changed := old.status is distinct from new.status;
  end if;

  -- Edições comuns da ficha não reabrem o fluxo editorial automaticamente.
  if not v_status_changed then
    return new;
  end if;

  if new.status in ('approved', 'published') then
    if new.content_state is distinct from 'structured'
      or not exists (
        select 1
        from public.recipe_ingredients i
        where i.recipe_id = new.id
           or exists (
             select 1
             from public.recipe_components rc
             where rc.recipe_id = new.id
               and rc.linked_recipe_id = i.recipe_id
           )
      )
      or not exists (
        select 1
        from public.recipe_steps s
        where s.recipe_id = new.id
           or exists (
             select 1
             from public.recipe_components rc
             where rc.recipe_id = new.id
               and rc.linked_recipe_id = s.recipe_id
           )
      )
    then
      raise exception 'CONTENT_REQUIRED: a receita precisa ter uma ficha estruturada, com ingredientes e modo de preparo.'
        using errcode = 'P0001';
    end if;

    if exists (
      select 1
      from public.review_flags f
      where f.resolved_at is null
        and f.severity in ('warning', 'blocker')
        and (
          f.recipe_id = new.id
          or exists (
            select 1
            from public.recipe_components rc
            where rc.recipe_id = new.id
              and rc.linked_recipe_id = f.recipe_id
          )
        )
    ) then
      raise exception 'FLAGS_PENDING: existem pontos de revisão em aberto nesta ficha ou em seus componentes vinculados.'
        using errcode = 'P0001';
    end if;
  end if;

  if new.status = 'approved' then
    new.reviewed_at := now();
    new.reviewed_by := coalesce(auth.uid(), new.reviewed_by);
  end if;

  if new.status = 'published' then
    if new.reviewed_at is null then
      raise exception 'APPROVAL_REQUIRED: a ficha precisa passar pela aprovação humana antes da publicação.'
        using errcode = 'P0001';
    end if;

    select d.commercial_permission
      into v_permission
    from public.source_documents d
    where d.id = new.source_document_id;

    if v_permission is distinct from 'confirmed' then
      raise exception 'PERMISSION_REQUIRED: confirme a permissão comercial do documento de origem antes da publicação.'
        using errcode = 'P0001';
    end if;

    if exists (
      select 1
      from public.recipe_components rc
      join public.recipes linked_recipe on linked_recipe.id = rc.linked_recipe_id
      where rc.recipe_id = new.id
        and linked_recipe.status <> 'published'
    ) then
      raise exception 'LINKED_COMPONENT_UNPUBLISHED: publique antes os componentes compartilhados desta receita.'
        using errcode = 'P0001';
    end if;

    new.published_at := coalesce(new.published_at, now());
  end if;

  return new;
end
$function$;
