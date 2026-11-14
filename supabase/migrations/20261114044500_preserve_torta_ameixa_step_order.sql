-- Preserva a sequência original da Torta de Ameixa com Nozes no modo cozinheiro.
-- O fechamento da massa e a ida ao forno acontecem depois do recheio e antes da cobertura.
begin;

update public.recipe_components rc
set position=4, updated_at=now()
from public.recipes r
where rc.recipe_id=r.id
  and r.slug='torta-de-ameixa-com-nozes'
  and rc.role='cobertura'
  and rc.position=3;

insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select r.id,'montagem','Fechamento e forno',1,3,8,8
from public.recipes r
where r.slug='torta-de-ameixa-com-nozes' and r.source_page_start=8
  and not exists (
    select 1 from public.recipe_components rc
    where rc.recipe_id=r.id and rc.position=3
  );

update public.recipe_steps s
set component_id=rc.id, updated_at=now()
from public.recipes r
join public.recipe_components rc on rc.recipe_id=r.id
where r.slug='torta-de-ameixa-com-nozes'
  and s.recipe_id=r.id
  and s.position=6
  and s.component_id is not null
  and rc.role='montagem'
  and rc.position=3;

commit;