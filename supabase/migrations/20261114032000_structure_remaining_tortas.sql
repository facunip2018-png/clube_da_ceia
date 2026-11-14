-- Completa a estrutura das tortas restantes com grupos sustentados pelas listas e instruções da apostila.
-- Torta de Pêra permanece sem divisão: as instruções intercalam massa, recheio e montagem,
-- e a visualização atual agrupa etapas por componente, o que alteraria a ordem original.
begin;

insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 9, 9
from public.recipes rec
where rec.slug='torta-de-limao' and rec.source_page_start=9
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-limao' and rec.source_page_start=9
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 5;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-limao' and rec.source_page_start=9
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1,2,3);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Recheio', 1, 2, 9, 9
from public.recipes rec
where rec.slug='torta-de-limao' and rec.source_page_start=9
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-limao' and rec.source_page_start=9
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 6 and 9;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-limao' and rec.source_page_start=9
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (4);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura', 1, 3, 9, 9
from public.recipes rec
where rec.slug='torta-de-limao' and rec.source_page_start=9
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-limao' and rec.source_page_start=9
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura'
  and ri.position between 10 and 12;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-limao' and rec.source_page_start=9
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura'
  and rs.position in (5,6,7);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme', 1, 1, 11, 11
from public.recipes rec
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme'
  and ri.position between 1 and 5;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme'
  and rs.position in (1,2,3);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem', 1, 2, 11, 11
from public.recipes rec
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem'
  and ri.position between 6 and 6;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem'
  and rs.position in (4,5,6);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura de chocolate', 1, 3, 11, 11
from public.recipes rec
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura'
  and ri.position between 7 and 9;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura'
  and rs.position in (7,8);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Finalização', 1, 4, 11, 11
from public.recipes rec
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=4);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='finalizacao'
  and ri.position between 10 and 10;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-holandesa' and rec.source_page_start=11
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao'
  and rs.position in (9);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 16, 16
from public.recipes rec
where rec.slug='torta-integral' and rec.source_page_start=16
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-integral' and rec.source_page_start=16
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 6;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-integral' and rec.source_page_start=16
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Recheio', 1, 2, 16, 16
from public.recipes rec
where rec.slug='torta-integral' and rec.source_page_start=16
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-integral' and rec.source_page_start=16
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 7 and 11;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-integral' and rec.source_page_start=16
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (2);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem', 1, 3, 16, 16
from public.recipes rec
where rec.slug='torta-integral' and rec.source_page_start=16
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);



update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-integral' and rec.source_page_start=16
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem'
  and rs.position in (3);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Recheio', 1, 1, 19, 19
from public.recipes rec
where rec.slug='torta-de-maca' and rec.source_page_start=19
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-maca' and rec.source_page_start=19
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 10 and 14;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-maca' and rec.source_page_start=19
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (1);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 2, 19, 19
from public.recipes rec
where rec.slug='torta-de-maca' and rec.source_page_start=19
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-maca' and rec.source_page_start=19
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 6;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-maca' and rec.source_page_start=19
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (2,3);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura', 1, 3, 19, 19
from public.recipes rec
where rec.slug='torta-de-maca' and rec.source_page_start=19
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-maca' and rec.source_page_start=19
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura'
  and ri.position between 7 and 9;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-maca' and rec.source_page_start=19
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura'
  and rs.position in (4,5);

commit;