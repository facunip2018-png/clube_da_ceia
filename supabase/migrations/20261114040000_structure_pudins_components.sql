-- Estrutura as 13 fichas de pudins com caldas, massas, ganaches, coberturas e etapas na ordem da apostila.
-- As caldas/coberturas citadas em materiais de apoio permanecem também na biblioteca de apoio.
begin;

insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa do pudim', 1, 1, 12, 12
from public.recipes rec
where rec.slug='pudim-tradicional' and rec.source_page_start=12
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-tradicional' and rec.source_page_start=12
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-tradicional' and rec.source_page_start=12
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'calda', 'Calda e montagem', 1, 2, 12, 12
from public.recipes rec
where rec.slug='pudim-tradicional' and rec.source_page_start=12
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-tradicional' and rec.source_page_start=12
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='calda' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-tradicional' and rec.source_page_start=12
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='calda' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e finalização', 1, 3, 12, 12
from public.recipes rec
where rec.slug='pudim-tradicional' and rec.source_page_start=12
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-tradicional' and rec.source_page_start=12
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[5,6]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa do pudim de café', 1, 1, 13, 13
from public.recipes rec
where rec.slug='pudim-de-cafe' and rec.source_page_start=13
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-cafe' and rec.source_page_start=13
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-cafe' and rec.source_page_start=13
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'calda', 'Calda e montagem', 1, 2, 13, 13
from public.recipes rec
where rec.slug='pudim-de-cafe' and rec.source_page_start=13
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-cafe' and rec.source_page_start=13
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='calda' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-cafe' and rec.source_page_start=13
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='calda' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e finalização', 1, 3, 13, 13
from public.recipes rec
where rec.slug='pudim-de-cafe' and rec.source_page_start=13
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-cafe' and rec.source_page_start=13
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[5,6,7]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa de chocolate', 1, 1, 14, 14
from public.recipes rec
where rec.slug='pudim-de-chocolate-meio-amargo' and rec.source_page_start=14
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-meio-amargo' and rec.source_page_start=14
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5,6,7]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-meio-amargo' and rec.source_page_start=14
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'calda', 'Calda de chocolate e montagem', 1, 2, 14, 14
from public.recipes rec
where rec.slug='pudim-de-chocolate-meio-amargo' and rec.source_page_start=14
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-meio-amargo' and rec.source_page_start=14
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='calda' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-meio-amargo' and rec.source_page_start=14
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='calda' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e finalização', 1, 3, 14, 14
from public.recipes rec
where rec.slug='pudim-de-chocolate-meio-amargo' and rec.source_page_start=14
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-meio-amargo' and rec.source_page_start=14
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[5,6,7]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa de coco', 1, 1, 15, 15
from public.recipes rec
where rec.slug='pudim-de-coco' and rec.source_page_start=15
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-coco' and rec.source_page_start=15
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-coco' and rec.source_page_start=15
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'calda', 'Calda e montagem', 1, 2, 15, 15
from public.recipes rec
where rec.slug='pudim-de-coco' and rec.source_page_start=15
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-coco' and rec.source_page_start=15
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='calda' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-coco' and rec.source_page_start=15
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='calda' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e finalização', 1, 3, 15, 15
from public.recipes rec
where rec.slug='pudim-de-coco' and rec.source_page_start=15
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-coco' and rec.source_page_start=15
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[5,6]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa de doce de leite', 1, 1, 16, 16
from public.recipes rec
where rec.slug='pudim-de-doce-de-leite' and rec.source_page_start=16
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-doce-de-leite' and rec.source_page_start=16
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-doce-de-leite' and rec.source_page_start=16
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'calda', 'Calda e montagem', 1, 2, 16, 16
from public.recipes rec
where rec.slug='pudim-de-doce-de-leite' and rec.source_page_start=16
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-doce-de-leite' and rec.source_page_start=16
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='calda' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-doce-de-leite' and rec.source_page_start=16
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='calda' and rs.position = any(array[3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e finalização', 1, 3, 16, 16
from public.recipes rec
where rec.slug='pudim-de-doce-de-leite' and rec.source_page_start=16
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-doce-de-leite' and rec.source_page_start=16
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[4,5]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa de pistache', 1, 1, 17, 17
from public.recipes rec
where rec.slug='pudim-de-pistache' and rec.source_page_start=17
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-pistache' and rec.source_page_start=17
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-pistache' and rec.source_page_start=17
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'calda', 'Calda e montagem', 1, 2, 17, 17
from public.recipes rec
where rec.slug='pudim-de-pistache' and rec.source_page_start=17
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-pistache' and rec.source_page_start=17
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='calda' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-pistache' and rec.source_page_start=17
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='calda' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e finalização', 1, 3, 17, 17
from public.recipes rec
where rec.slug='pudim-de-pistache' and rec.source_page_start=17
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-pistache' and rec.source_page_start=17
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[5,6]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'base', 'Preparação da forma', 1, 1, 18, 18
from public.recipes rec
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='base' and ri.position = any(array[8]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='base' and rs.position = any(array[1]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Ganache de chocolate branco', 1, 2, 18, 18
from public.recipes rec
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[3,7]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa do pudim', 1, 3, 18, 18
from public.recipes rec
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,4,5,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[3,4,5]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e cobertura de morango', 1, 4, 18, 18
from public.recipes rec
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=4);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='finalizacao' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-chocolate-branco-com-cobertura-de-doce-de-morango' and rec.source_page_start=18
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[6,7]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa de leite Ninho', 1, 1, 19, 19
from public.recipes rec
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella' and rec.source_page_start=19
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella' and rec.source_page_start=19
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella' and rec.source_page_start=19
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Preparação da forma', 1, 2, 19, 19
from public.recipes rec
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella' and rec.source_page_start=19
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella' and rec.source_page_start=19
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e resfriamento', 1, 3, 19, 19
from public.recipes rec
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella' and rec.source_page_start=19
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella' and rec.source_page_start=19
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[5]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura de Nutella', 1, 4, 19, 19
from public.recipes rec
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella' and rec.source_page_start=19
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=4);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella' and rec.source_page_start=19
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella' and rec.source_page_start=19
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura' and rs.position = any(array[6]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa Romeu e Julieta', 1, 1, 20, 20
from public.recipes rec
where rec.slug='pudim-romeu-e-julieta' and rec.source_page_start=20
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-romeu-e-julieta' and rec.source_page_start=20
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5,6,7]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-romeu-e-julieta' and rec.source_page_start=20
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Preparação da forma', 1, 2, 20, 20
from public.recipes rec
where rec.slug='pudim-romeu-e-julieta' and rec.source_page_start=20
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-romeu-e-julieta' and rec.source_page_start=20
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e resfriamento', 1, 3, 20, 20
from public.recipes rec
where rec.slug='pudim-romeu-e-julieta' and rec.source_page_start=20
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-romeu-e-julieta' and rec.source_page_start=20
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura de goiabada', 1, 4, 20, 20
from public.recipes rec
where rec.slug='pudim-romeu-e-julieta' and rec.source_page_start=20
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=4);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-romeu-e-julieta' and rec.source_page_start=20
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-romeu-e-julieta' and rec.source_page_start=20
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura' and rs.position = any(array[5]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa de Ovomaltine', 1, 1, 21, 21
from public.recipes rec
where rec.slug='pudim-de-ovomaltine' and rec.source_page_start=21
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ovomaltine' and rec.source_page_start=21
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5,6,7]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ovomaltine' and rec.source_page_start=21
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'calda', 'Calda de chocolate e montagem', 1, 2, 21, 21
from public.recipes rec
where rec.slug='pudim-de-ovomaltine' and rec.source_page_start=21
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ovomaltine' and rec.source_page_start=21
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='calda' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ovomaltine' and rec.source_page_start=21
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='calda' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e finalização', 1, 3, 21, 21
from public.recipes rec
where rec.slug='pudim-de-ovomaltine' and rec.source_page_start=21
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ovomaltine' and rec.source_page_start=21
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[5,6]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa de leite Ninho', 1, 1, 22, 22
from public.recipes rec
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella-sem-forno' and rec.source_page_start=22
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella-sem-forno' and rec.source_page_start=22
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5,6,7]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella-sem-forno' and rec.source_page_start=22
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2,3,4,5]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura de Nutella', 1, 2, 22, 22
from public.recipes rec
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella-sem-forno' and rec.source_page_start=22
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella-sem-forno' and rec.source_page_start=22
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-ninho-com-cobertura-de-nutella-sem-forno' and rec.source_page_start=22
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura' and rs.position = any(array[6]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa de coco diet', 1, 1, 23, 23
from public.recipes rec
where rec.slug='pudim-de-coco-diet' and rec.source_page_start=23
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-coco-diet' and rec.source_page_start=23
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5,6,7,8]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-coco-diet' and rec.source_page_start=23
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Calda de coco diet e finalização', 1, 2, 23, 23
from public.recipes rec
where rec.slug='pudim-de-coco-diet' and rec.source_page_start=23
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-coco-diet' and rec.source_page_start=23
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-de-coco-diet' and rec.source_page_start=23
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa do pudim diet', 1, 1, 24, 24
from public.recipes rec
where rec.slug='pudim-diet' and rec.source_page_start=24
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-diet' and rec.source_page_start=24
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[2,3,4,5,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-diet' and rec.source_page_start=24
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[1,2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'calda', 'Calda diet e montagem', 1, 2, 24, 24
from public.recipes rec
where rec.slug='pudim-diet' and rec.source_page_start=24
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-diet' and rec.source_page_start=24
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='calda' and ri.position = any(array[1]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-diet' and rec.source_page_start=24
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='calda' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Cocção e finalização', 1, 3, 24, 24
from public.recipes rec
where rec.slug='pudim-diet' and rec.source_page_start=24
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pudim-diet' and rec.source_page_start=24
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[5,6]);

commit;
