-- Estrutura a Torta de Pêra sem alterar a sequência do preparo.
-- As etapas intercaladas são separadas em partes sequenciais: massa, recheio,
-- montagem e finalização. Os ingredientes são mantidos em suas listas originais.
begin;

insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select r.id, v.role, v.title, 1, v.position, 17, 17
from public.recipes r
cross join (values
  ('massa'::text,'Massa'::text,1),
  ('recheio'::text,'Recheio de pera'::text,2),
  ('montagem'::text,'Montagem'::text,3),
  ('finalizacao'::text,'Finalização'::text,4)
) v(role,title,position)
where r.slug='torta-de-pera' and r.source_page_start=17
  and not exists (
    select 1 from public.recipe_components rc
    where rc.recipe_id=r.id and rc.position=v.position
  );

update public.recipe_ingredients i
set component_id=rc.id, updated_at=now()
from public.recipes r
join public.recipe_components rc on rc.recipe_id=r.id
where r.slug='torta-de-pera' and r.source_page_start=17
  and i.recipe_id=r.id and i.component_id is null
  and (
    (rc.role='massa' and i.position between 1 and 5)
    or (rc.role='finalizacao' and i.position between 6 and 8)
    or (rc.role='recheio' and i.position between 9 and 15)
  );

update public.recipe_steps s
set component_id=rc.id, updated_at=now()
from public.recipes r
join public.recipe_components rc on rc.recipe_id=r.id
where r.slug='torta-de-pera' and r.source_page_start=17
  and s.recipe_id=r.id and s.component_id is null
  and (
    (rc.role='massa' and s.position=1)
    or (rc.role='recheio' and s.position in (2,3))
    or (rc.role='montagem' and s.position in (4,5))
    or (rc.role='finalizacao' and s.position=6)
  );

commit;