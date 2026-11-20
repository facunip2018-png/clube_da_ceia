-- Restaura a revisão editorial no servidor sem retirar do ar conteúdo já publicado.
-- A regra só valida transições para approved/published; atualizações comuns em fichas
-- já publicadas não são retroativamente bloqueadas.
create or replace function public.guard_recipe_status()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_permission text;
  v_ingredient_count integer := 0;
  v_step_count integer := 0;
begin
  if tg_op = 'UPDATE' and new.status is not distinct from old.status then
    return new;
  end if;

  if new.status not in ('approved', 'published') then
    return new;
  end if;

  if new.content_state is distinct from 'structured' then
    raise exception 'CONTENT_REQUIRED: a receita ainda não possui ficha estruturada.'
      using errcode = 'P0001';
  end if;

  -- A composição é recursiva: partes compartilhadas também contam como conteúdo.
  -- UNION (não UNION ALL) impede repetição infinita se houver algum ciclo antigo.
  with recursive recipe_tree(id) as (
    select new.id
    union
    select component.linked_recipe_id
    from public.recipe_components component
    join recipe_tree parent on parent.id = component.recipe_id
    where component.linked_recipe_id is not null
  )
  select
    (select count(*)::integer
       from public.recipe_ingredients ingredient
      where ingredient.recipe_id in (select id from recipe_tree)),
    (select count(*)::integer
       from public.recipe_steps step
      where step.recipe_id in (select id from recipe_tree))
  into v_ingredient_count, v_step_count;

  -- Componentes informativos podem conter somente instruções (ex.: escolha e
  -- conservação do pão). Receitas e variações precisam de ingredientes e etapas.
  if new.kind = 'component' then
    if v_ingredient_count = 0 and v_step_count = 0 then
      raise exception 'CONTENT_REQUIRED: o componente precisa ter ingredientes ou instruções.'
        using errcode = 'P0001';
    end if;
  elsif v_ingredient_count = 0 or v_step_count = 0 then
    raise exception 'CONTENT_REQUIRED: a receita precisa ter ingredientes e modo de preparo.'
      using errcode = 'P0001';
  end if;

  -- Alertas ainda não resolvidos em qualquer parte da composição impedem aprovação.
  with recursive recipe_tree(id) as (
    select new.id
    union
    select component.linked_recipe_id
    from public.recipe_components component
    join recipe_tree parent on parent.id = component.recipe_id
    where component.linked_recipe_id is not null
  )
  if exists (
    select 1
    from public.review_flags flag
    where flag.recipe_id in (select id from recipe_tree)
      and flag.resolved_at is null
      and flag.severity in ('warning', 'blocker')
  ) then
    raise exception 'FLAGS_PENDING: existem pontos de revisão em aberto nesta ficha ou em suas partes.'
      using errcode = 'P0001';
  end if;

  if new.status = 'approved' then
    new.reviewed_at := coalesce(new.reviewed_at, now());
    new.reviewed_by := coalesce(new.reviewed_by, auth.uid());
    return new;
  end if;

  if new.status = 'published' then
    if new.reviewed_at is null then
      raise exception 'APPROVAL_REQUIRED: a ficha precisa ser aprovada na revisão antes de ser publicada.'
        using errcode = 'P0001';
    end if;

    -- Todos os documentos usados pela ficha e pelas partes compartilhadas
    -- precisam ter permissão comercial confirmada.
    with recursive recipe_tree(id) as (
      select new.id
      union
      select component.linked_recipe_id
      from public.recipe_components component
      join recipe_tree parent on parent.id = component.recipe_id
      where component.linked_recipe_id is not null
    )
    if exists (
      select 1
      from public.recipes linked
      left join public.source_documents document on document.id = linked.source_document_id
      where linked.id in (select id from recipe_tree)
        and (linked.source_document_id is null or document.commercial_permission is distinct from 'confirmed')
    ) then
      raise exception 'PERMISSION_REQUIRED: confirme a permissão comercial de todos os materiais usados pela ficha.'
        using errcode = 'P0001';
    end if;

    -- Componentes compartilhados precisam estar publicados antes da receita que os usa.
    with recursive recipe_tree(id) as (
      select new.id
      union
      select component.linked_recipe_id
      from public.recipe_components component
      join recipe_tree parent on parent.id = component.recipe_id
      where component.linked_recipe_id is not null
    )
    if exists (
      select 1
      from public.recipes linked
      where linked.id in (select id from recipe_tree)
        and linked.id <> new.id
        and linked.status <> 'published'
    ) then
      raise exception 'LINKED_COMPONENT_UNPUBLISHED: publique antes os componentes compartilhados desta receita.'
        using errcode = 'P0001';
    end if;

    new.published_at := coalesce(new.published_at, now());
  end if;

  return new;
end
$function$;

-- A importação automática não publica conteúdo diretamente.
-- Com autorização confirmada entra em revisão; sem autorização fica bloqueada.
-- Cada ficha importada recebe um alerta explícito para conferência com o PDF.
create or replace function public.admin_import_pdf_recipes(p_document_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $function$
declare
  v_doc public.source_documents%rowtype;
  v_collection_id uuid;
  v_collection_name text;
  v_collection_slug text;
  v_recipe jsonb;
  v_ingredient jsonb;
  v_step jsonb;
  v_material jsonb;
  v_recipe_id uuid;
  v_ingredient_id uuid;
  v_title text;
  v_slug text;
  v_base_slug text;
  v_name text;
  v_name_slug text;
  v_position integer;
  v_ingredient_position integer;
  v_step_position integer;
  v_created integer := 0;
  v_skipped integer := 0;
  v_materials integer := 0;
  v_permission_ok boolean;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'Apenas administradores podem importar documentos.';
  end if;

  select * into v_doc
  from public.source_documents
  where id = p_document_id
  for update;

  if not found then
    raise exception 'Documento não encontrado.';
  end if;

  if v_doc.storage_path is null or v_doc.file_status <> 'stored' then
    raise exception 'Envie o PDF antes de iniciar a leitura.';
  end if;

  if jsonb_typeof(p_payload->'recipes') <> 'array' then
    raise exception 'A leitura não retornou uma lista de receitas válida.';
  end if;

  v_collection_id := v_doc.collection_id;
  v_collection_name := nullif(trim(p_payload#>>'{collection,name}'), '');

  if v_collection_id is null and v_collection_name is not null then
    v_collection_slug := trim(both '-' from regexp_replace(
      lower(translate(v_collection_name,
        'áàâãäéèêëíìîïóòôõöúùûüçñ',
        'aaaaaeeeeiiiiooooouuuucn')),
      '[^a-z0-9]+', '-', 'g'));
    if v_collection_slug = '' then
      v_collection_slug := 'colecao-' || substr(md5(v_collection_name), 1, 8);
    end if;
    insert into public.collections (slug, name, description, experience, position, is_visible)
    values (
      v_collection_slug,
      v_collection_name,
      nullif(trim(p_payload#>>'{collection,description}'), ''),
      'catalog',
      coalesce((select max(position) + 1 from public.collections), 0),
      true
    )
    on conflict (slug) do update set name = excluded.name
    returning id into v_collection_id;

    update public.source_documents
    set collection_id = v_collection_id
    where id = p_document_id;
  end if;

  if v_collection_id is null then
    raise exception 'Não foi possível identificar a categoria deste PDF.';
  end if;

  v_permission_ok := v_doc.commercial_permission = 'confirmed';
  select coalesce(max(position), 0) + 1 into v_position
  from public.recipes
  where collection_id = v_collection_id;

  for v_recipe in
    select value from jsonb_array_elements(p_payload->'recipes')
  loop
    v_title := nullif(trim(v_recipe->>'title'), '');

    if v_title is null
       or jsonb_typeof(v_recipe->'ingredients') <> 'array'
       or jsonb_array_length(v_recipe->'ingredients') = 0
       or jsonb_typeof(v_recipe->'steps') <> 'array'
       or jsonb_array_length(v_recipe->'steps') = 0 then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    if exists (
      select 1 from public.recipes
      where source_document_id = p_document_id
        and lower(title) = lower(v_title)
        and status <> 'archived'
    ) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    v_base_slug := trim(both '-' from regexp_replace(
      lower(translate(v_title,
        'áàâãäéèêëíìîïóòôõöúùûüçñ',
        'aaaaaeeeeiiiiooooouuuucn')),
      '[^a-z0-9]+', '-', 'g'));
    if v_base_slug = '' then
      v_base_slug := 'receita-' || substr(md5(v_title), 1, 8);
    end if;
    v_slug := v_base_slug;
    while exists (select 1 from public.recipes where slug = v_slug) loop
      v_slug := v_base_slug || '-' || substr(md5(v_title || clock_timestamp()::text), 1, 6);
    end loop;

    insert into public.recipes (
      slug, collection_id, source_document_id, kind, title, original_title,
      original_language, translation_status, description, difficulty,
      yield_text, prep_minutes, cook_minutes, bake_minutes, chill_minutes,
      rest_minutes, source_page_start, source_page_end, content_state,
      status, position
    ) values (
      v_slug, v_collection_id, p_document_id, 'recipe', v_title,
      nullif(trim(v_recipe->>'original_title'), ''),
      coalesce(nullif(v_recipe->>'original_language', ''), 'pt-BR'),
      case when coalesce(v_recipe->>'original_language', 'pt-BR') = 'pt-BR' then 'not_needed' else 'pending' end,
      nullif(trim(v_recipe->>'description'), ''),
      case when v_recipe->>'difficulty' in ('facil','media','dificil') then v_recipe->>'difficulty' else null end,
      nullif(trim(v_recipe->>'yield_text'), ''),
      nullif(v_recipe->>'prep_minutes','')::integer,
      nullif(v_recipe->>'cook_minutes','')::integer,
      nullif(v_recipe->>'bake_minutes','')::integer,
      nullif(v_recipe->>'chill_minutes','')::integer,
      nullif(v_recipe->>'rest_minutes','')::integer,
      nullif(v_recipe->>'source_page_start','')::integer,
      nullif(v_recipe->>'source_page_end','')::integer,
      'structured', 'draft', v_position
    ) returning id into v_recipe_id;

    v_ingredient_position := 0;
    for v_ingredient in select value from jsonb_array_elements(v_recipe->'ingredients')
    loop
      v_name := nullif(trim(v_ingredient->>'display_name'), '');
      if v_name is null then
        continue;
      end if;
      v_name_slug := trim(both '-' from regexp_replace(
        lower(translate(v_name,
          'áàâãäéèêëíìîïóòôõöúùûüçñ',
          'aaaaaeeeeiiiiooooouuuucn')),
        '[^a-z0-9]+', '-', 'g'));
      if v_name_slug = '' then
        v_name_slug := 'ingrediente-' || substr(md5(v_name), 1, 8);
      end if;

      insert into public.ingredients (slug, name)
      values (v_name_slug, v_name)
      on conflict (slug) do update set name = excluded.name
      returning id into v_ingredient_id;

      v_ingredient_position := v_ingredient_position + 1;
      insert into public.recipe_ingredients (
        recipe_id, ingredient_id, position, quantity, quantity_max, unit,
        quantity_text, display_name, preparation, scaling, is_optional,
        original_text, source_page, needs_review
      ) values (
        v_recipe_id, v_ingredient_id, v_ingredient_position,
        nullif(v_ingredient->>'quantity','')::numeric,
        nullif(v_ingredient->>'quantity_max','')::numeric,
        nullif(trim(v_ingredient->>'unit'),''),
        nullif(trim(v_ingredient->>'quantity_text'),''),
        v_name,
        nullif(trim(v_ingredient->>'preparation'),''),
        'linear',
        coalesce((v_ingredient->>'is_optional')::boolean, false),
        coalesce(nullif(trim(v_ingredient->>'original_text'), ''), v_name),
        nullif(v_ingredient->>'source_page','')::integer,
        false
      );
    end loop;

    v_step_position := 0;
    for v_step in select value from jsonb_array_elements(v_recipe->'steps')
    loop
      if nullif(trim(v_step->>'instruction'), '') is null then
        continue;
      end if;
      v_step_position := v_step_position + 1;
      insert into public.recipe_steps (
        recipe_id, position, instruction, original_text, tip, source_page, needs_review
      ) values (
        v_recipe_id, v_step_position,
        trim(v_step->>'instruction'),
        nullif(trim(v_step->>'original_text'), ''),
        nullif(trim(v_step->>'tip'), ''),
        nullif(v_step->>'source_page','')::integer,
        false
      );
    end loop;

    if v_ingredient_position = 0 or v_step_position = 0 then
      delete from public.recipes where id = v_recipe_id;
      v_skipped := v_skipped + 1;
      continue;
    end if;

    if v_permission_ok then
      update public.recipes
      set status = 'review'
      where id = v_recipe_id;
    else
      update public.recipes
      set status = 'pending_permission'
      where id = v_recipe_id;
    end if;

    insert into public.review_flags (
      recipe_id, entity, entity_id, field, severity, message,
      source_page
    ) values (
      v_recipe_id, 'recipe', v_recipe_id, 'automatic_import', 'warning',
      'Conteúdo importado automaticamente. Conferir ingredientes, quantidades, etapas e correspondência com o PDF original antes da aprovação.',
      nullif(v_recipe->>'source_page_start','')::integer
    );

    v_created := v_created + 1;
    v_position := v_position + 1;
  end loop;

  for v_material in
    select value from jsonb_array_elements(coalesce(p_payload->'support_materials', '[]'::jsonb))
  loop
    if nullif(trim(v_material->>'title'), '') is null
       or nullif(trim(v_material->>'body'), '') is null then
      continue;
    end if;
    insert into public.support_materials (
      slug, kind, title, body, source_document_id, source_page, position, is_visible
    ) values (
      'pdf-' || substr(md5(p_document_id::text || v_material->>'title' || coalesce(v_material->>'source_page','')),1,20),
      case when v_material->>'kind' in ('utensilios','ingredientes','dicas','orientacoes') then v_material->>'kind' else 'orientacoes' end,
      trim(v_material->>'title'),
      trim(v_material->>'body'),
      p_document_id,
      nullif(v_material->>'source_page','')::integer,
      coalesce((select max(position) + 1 from public.support_materials), 0),
      true
    )
    on conflict (slug) do nothing;
    if found then v_materials := v_materials + 1; end if;
  end loop;

  update public.source_documents
  set import_notes = concat_ws(E'\n', nullif(import_notes, ''),
      'Leitura automática em ' || to_char(now(), 'YYYY-MM-DD HH24:MI') ||
      ': ' || v_created || ' receita(s) criada(s), ' || v_skipped ||
      ' ignorada(s), ' || v_materials || ' material(is) de apoio.')
  where id = p_document_id;

  return jsonb_build_object(
    'created', v_created,
    'skipped', v_skipped,
    'support_materials', v_materials,
    'published', false,
    'awaiting_review', v_permission_ok,
    'awaiting_permission', not v_permission_ok
  );
end;
$function$;

revoke all on function public.admin_import_pdf_recipes(uuid, jsonb) from public, anon;
grant execute on function public.admin_import_pdf_recipes(uuid, jsonb) to authenticated;
