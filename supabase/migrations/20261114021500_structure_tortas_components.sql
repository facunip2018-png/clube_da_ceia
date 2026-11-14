-- Estrutura componentes de nove tortas com grupos e instruções explícitos nas páginas de origem.
-- Idempotente: cria componentes ausentes e só associa registros ainda sem componente.
begin;

insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 6, 6
from public.recipes rec
where rec.slug='torta-de-banana-e-coco' and rec.source_page_start=6
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=1
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-banana-e-coco' and rec.source_page_start=6
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 3;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-banana-e-coco' and rec.source_page_start=6
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1,2,3);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Recheio', 1, 2, 6, 6
from public.recipes rec
where rec.slug='torta-de-banana-e-coco' and rec.source_page_start=6
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=2
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-banana-e-coco' and rec.source_page_start=6
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 4 and 8;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-banana-e-coco' and rec.source_page_start=6
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (4,5);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura', 1, 3, 6, 6
from public.recipes rec
where rec.slug='torta-de-banana-e-coco' and rec.source_page_start=6
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=3
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-banana-e-coco' and rec.source_page_start=6
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura'
  and ri.position between 9 and 9;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-banana-e-coco' and rec.source_page_start=6
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura'
  and rs.position in (6);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 7, 7
from public.recipes rec
where rec.slug='torta-de-chantilly-com-maracuja' and rec.source_page_start=7
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=1
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-chantilly-com-maracuja' and rec.source_page_start=7
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 2;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-chantilly-com-maracuja' and rec.source_page_start=7
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme', 1, 2, 7, 7
from public.recipes rec
where rec.slug='torta-de-chantilly-com-maracuja' and rec.source_page_start=7
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=2
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-chantilly-com-maracuja' and rec.source_page_start=7
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme'
  and ri.position between 3 and 9;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-chantilly-com-maracuja' and rec.source_page_start=7
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme'
  and rs.position in (2,3,4);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura', 1, 3, 7, 7
from public.recipes rec
where rec.slug='torta-de-chantilly-com-maracuja' and rec.source_page_start=7
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=3
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-chantilly-com-maracuja' and rec.source_page_start=7
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura'
  and ri.position between 10 and 13;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-chantilly-com-maracuja' and rec.source_page_start=7
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura'
  and rs.position in (5,6);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 8, 8
from public.recipes rec
where rec.slug='torta-de-ameixa-com-nozes' and rec.source_page_start=8
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=1
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-ameixa-com-nozes' and rec.source_page_start=8
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 5;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-ameixa-com-nozes' and rec.source_page_start=8
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1,2,3,6);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Recheio', 1, 2, 8, 8
from public.recipes rec
where rec.slug='torta-de-ameixa-com-nozes' and rec.source_page_start=8
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=2
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-ameixa-com-nozes' and rec.source_page_start=8
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 6 and 8;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-ameixa-com-nozes' and rec.source_page_start=8
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (4,5);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura', 1, 3, 8, 8
from public.recipes rec
where rec.slug='torta-de-ameixa-com-nozes' and rec.source_page_start=8
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=3
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-ameixa-com-nozes' and rec.source_page_start=8
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura'
  and ri.position between 9 and 10;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-ameixa-com-nozes' and rec.source_page_start=8
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura'
  and rs.position in (7);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 10, 10
from public.recipes rec
where rec.slug='torta-doce-de-milho' and rec.source_page_start=10
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=1
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-doce-de-milho' and rec.source_page_start=10
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 2;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-doce-de-milho' and rec.source_page_start=10
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1,2);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Recheio', 1, 2, 10, 10
from public.recipes rec
where rec.slug='torta-doce-de-milho' and rec.source_page_start=10
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=2
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-doce-de-milho' and rec.source_page_start=10
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 3 and 7;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-doce-de-milho' and rec.source_page_start=10
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (3,4,5);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 12, 12
from public.recipes rec
where rec.slug='torta-mousse-de-mel' and rec.source_page_start=12
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=1
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-mousse-de-mel' and rec.source_page_start=12
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 2;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-mousse-de-mel' and rec.source_page_start=12
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Mousse de mel', 1, 2, 12, 12
from public.recipes rec
where rec.slug='torta-mousse-de-mel' and rec.source_page_start=12
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=2
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-mousse-de-mel' and rec.source_page_start=12
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 3 and 8;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-mousse-de-mel' and rec.source_page_start=12
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (2,3);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 13, 13
from public.recipes rec
where rec.slug='torta-de-manga' and rec.source_page_start=13
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=1
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-manga' and rec.source_page_start=13
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 2;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-manga' and rec.source_page_start=13
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Recheio de manga', 1, 2, 13, 13
from public.recipes rec
where rec.slug='torta-de-manga' and rec.source_page_start=13
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=2
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-manga' and rec.source_page_start=13
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 3 and 8;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-manga' and rec.source_page_start=13
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (2,3,4,5);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 14, 14
from public.recipes rec
where rec.slug='torta-romeu-e-julieta' and rec.source_page_start=14
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=1
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-romeu-e-julieta' and rec.source_page_start=14
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 2;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-romeu-e-julieta' and rec.source_page_start=14
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Recheio', 1, 2, 14, 14
from public.recipes rec
where rec.slug='torta-romeu-e-julieta' and rec.source_page_start=14
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=2
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-romeu-e-julieta' and rec.source_page_start=14
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 3 and 7;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-romeu-e-julieta' and rec.source_page_start=14
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (2,3);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura de goiabada', 1, 3, 14, 14
from public.recipes rec
where rec.slug='torta-romeu-e-julieta' and rec.source_page_start=14
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=3
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-romeu-e-julieta' and rec.source_page_start=14
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura'
  and ri.position between 8 and 8;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-romeu-e-julieta' and rec.source_page_start=14
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura'
  and rs.position in (4);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 15, 15
from public.recipes rec
where rec.slug='torta-de-nozes' and rec.source_page_start=15
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=1
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-nozes' and rec.source_page_start=15
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 2;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-nozes' and rec.source_page_start=15
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1,2);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Recheio de nozes', 1, 2, 15, 15
from public.recipes rec
where rec.slug='torta-de-nozes' and rec.source_page_start=15
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=2
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-nozes' and rec.source_page_start=15
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 3 and 8;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-nozes' and rec.source_page_start=15
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (3,4);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura de chantilly', 1, 3, 15, 15
from public.recipes rec
where rec.slug='torta-de-nozes' and rec.source_page_start=15
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=3
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-nozes' and rec.source_page_start=15
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura'
  and ri.position between 9 and 9;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-de-nozes' and rec.source_page_start=15
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura'
  and rs.position in (5);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Massa', 1, 1, 18, 18
from public.recipes rec
where rec.slug='torta-sorvete-de-cafe' and rec.source_page_start=18
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=1
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-sorvete-de-cafe' and rec.source_page_start=18
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa'
  and ri.position between 1 and 2;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-sorvete-de-cafe' and rec.source_page_start=18
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa'
  and rs.position in (1,2);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Recheio de sorvete e café', 1, 2, 18, 18
from public.recipes rec
where rec.slug='torta-sorvete-de-cafe' and rec.source_page_start=18
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=2
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-sorvete-de-cafe' and rec.source_page_start=18
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio'
  and ri.position between 3 and 4;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-sorvete-de-cafe' and rec.source_page_start=18
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio'
  and rs.position in (3,4);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura', 1, 3, 18, 18
from public.recipes rec
where rec.slug='torta-sorvete-de-cafe' and rec.source_page_start=18
  and not exists (
    select 1 from public.recipe_components existing
    where existing.recipe_id=rec.id and existing.position=3
  );

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-sorvete-de-cafe' and rec.source_page_start=18
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura'
  and ri.position between 5 and 5;

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='torta-sorvete-de-cafe' and rec.source_page_start=18
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura'
  and rs.position in (5);

commit;