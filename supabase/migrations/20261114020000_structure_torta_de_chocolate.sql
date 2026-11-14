-- Registra a estruturação inicial da Torta de Chocolate.
-- A receita já foi estruturada diretamente no banco; esta migração é idempotente
-- para manter o mesmo estado em ambientes que ainda não receberam os dados.
with target as (
  select id
  from public.recipes
  where slug = 'torta-de-chocolate'
    and source_page_start = 5
    and source_page_end = 5
),
components_to_create(role, title, position) as (
  values
    ('massa'::text, 'Massa'::text, 1),
    ('recheio'::text, 'Recheio'::text, 2),
    ('cobertura'::text, 'Cobertura'::text, 3)
),
inserted as (
  insert into public.recipe_components
    (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
  select target.id, spec.role, spec.title, 1, spec.position, 5, 5
  from target
  cross join components_to_create spec
  where not exists (
    select 1
    from public.recipe_components existing
    where existing.recipe_id = target.id
      and existing.position = spec.position
  )
  returning id
)
update public.recipe_ingredients ingredient
set component_id = component.id,
    updated_at = now()
from target,
     public.recipe_components component
where ingredient.recipe_id = target.id
  and component.recipe_id = target.id
  and ingredient.component_id is null
  and (
    (component.role = 'massa' and ingredient.position between 1 and 2)
    or (component.role = 'recheio' and ingredient.position between 3 and 5)
    or (component.role = 'cobertura' and ingredient.position between 6 and 7)
  );

with target as (
  select id
  from public.recipes
  where slug = 'torta-de-chocolate'
    and source_page_start = 5
    and source_page_end = 5
)
update public.recipe_steps step
set component_id = component.id,
    updated_at = now()
from target,
     public.recipe_components component
where step.recipe_id = target.id
  and component.recipe_id = target.id
  and step.component_id is null
  and (
    (component.role = 'massa' and step.position = 1)
    or (component.role = 'recheio' and step.position between 2 and 3)
    or (component.role = 'cobertura' and step.position = 4)
  );
