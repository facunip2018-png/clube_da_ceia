-- Corrige a associação da Torta de Chocolate conforme os títulos explícitos da página 5.
-- A lista original aparece nesta ordem: recheio (posições 1–3), massa (4–5) e cobertura (6–7).
-- As etapas seguem: massa (1), recheio (2–3) e cobertura (4).
-- Não cria componentes nem ingredientes; falha se a ficha existente divergir da fonte conferida.
begin;

do $migration$
declare
  target_recipe_id uuid;
  recipe_count integer;
  components_count integer;
  ingredients_count integer;
  ingredients_on_source_page integer;
  steps_count integer;
  steps_on_source_page integer;
begin
  select count(*)
    into recipe_count
  from public.recipes
  where slug = 'torta-de-chocolate'
    and kind = 'recipe'
    and source_page_start = 5
    and source_page_end = 5;

  if recipe_count > 1 then
    raise exception 'Mais de uma Torta de Chocolate foi encontrada na página 5; revisão manual necessária.';
  end if;

  if recipe_count = 1 then
    select id
      into target_recipe_id
    from public.recipes
    where slug = 'torta-de-chocolate'
      and kind = 'recipe'
      and source_page_start = 5
      and source_page_end = 5;

    select count(*)
      into components_count
    from public.recipe_components
    where recipe_id = target_recipe_id;

    if components_count <> 3
      or not exists (
        select 1 from public.recipe_components
        where recipe_id = target_recipe_id and role = 'massa' and title = 'Massa' and position = 1
      )
      or not exists (
        select 1 from public.recipe_components
        where recipe_id = target_recipe_id and role = 'recheio' and title = 'Recheio' and position = 2
      )
      or not exists (
        select 1 from public.recipe_components
        where recipe_id = target_recipe_id and role = 'cobertura' and title = 'Cobertura' and position = 3
      )
    then
      raise exception 'A Torta de Chocolate não possui exatamente os três componentes esperados; nenhum vínculo foi alterado.';
    end if;

    select count(*), count(*) filter (where source_page = 5)
      into ingredients_count, ingredients_on_source_page
    from public.recipe_ingredients
    where recipe_id = target_recipe_id;

    if ingredients_count <> 7
      or ingredients_on_source_page <> 7
      or (select count(distinct position) from public.recipe_ingredients where recipe_id = target_recipe_id) <> 7
      or (select min(position) from public.recipe_ingredients where recipe_id = target_recipe_id) <> 1
      or (select max(position) from public.recipe_ingredients where recipe_id = target_recipe_id) <> 7
    then
      raise exception 'A Torta de Chocolate não possui os 7 ingredientes esperados na página 5; nenhum vínculo foi alterado.';
    end if;

    select count(*), count(*) filter (where source_page = 5)
      into steps_count, steps_on_source_page
    from public.recipe_steps
    where recipe_id = target_recipe_id;

    if steps_count <> 4
      or steps_on_source_page <> 4
      or (select count(distinct position) from public.recipe_steps where recipe_id = target_recipe_id) <> 4
      or (select min(position) from public.recipe_steps where recipe_id = target_recipe_id) <> 1
      or (select max(position) from public.recipe_steps where recipe_id = target_recipe_id) <> 4
    then
      raise exception 'A Torta de Chocolate não possui as 4 etapas esperadas na página 5; nenhum vínculo foi alterado.';
    end if;

    update public.recipe_ingredients as ingredient
    set component_id = component.id,
        updated_at = now()
    from public.recipe_components as component
    where ingredient.recipe_id = target_recipe_id
      and ingredient.source_page = 5
      and component.recipe_id = target_recipe_id
      and (
        (component.role = 'recheio' and ingredient.position between 1 and 3)
        or (component.role = 'massa' and ingredient.position between 4 and 5)
        or (component.role = 'cobertura' and ingredient.position between 6 and 7)
      )
      and ingredient.component_id is distinct from component.id;

    update public.recipe_steps as step
    set component_id = component.id,
        updated_at = now()
    from public.recipe_components as component
    where step.recipe_id = target_recipe_id
      and step.source_page = 5
      and component.recipe_id = target_recipe_id
      and (
        (component.role = 'massa' and step.position = 1)
        or (component.role = 'recheio' and step.position between 2 and 3)
        or (component.role = 'cobertura' and step.position = 4)
      )
      and step.component_id is distinct from component.id;

    if exists (
      select 1
      from public.recipe_ingredients as ingredient
      where ingredient.recipe_id = target_recipe_id
        and not exists (
          select 1
          from public.recipe_components as component
          where component.id = ingredient.component_id
            and component.recipe_id = target_recipe_id
            and (
              (component.role = 'recheio' and ingredient.position between 1 and 3)
              or (component.role = 'massa' and ingredient.position between 4 and 5)
              or (component.role = 'cobertura' and ingredient.position between 6 and 7)
            )
        )
    ) then
      raise exception 'Há ingrediente da Torta de Chocolate sem o componente confirmado pela página 5.';
    end if;

    if exists (
      select 1
      from public.recipe_steps as step
      where step.recipe_id = target_recipe_id
        and not exists (
          select 1
          from public.recipe_components as component
          where component.id = step.component_id
            and component.recipe_id = target_recipe_id
            and (
              (component.role = 'massa' and step.position = 1)
              or (component.role = 'recheio' and step.position between 2 and 3)
              or (component.role = 'cobertura' and step.position = 4)
            )
        )
    ) then
      raise exception 'Há etapa da Torta de Chocolate sem o componente confirmado pela página 5.';
    end if;
  end if;
end
$migration$;

commit;
