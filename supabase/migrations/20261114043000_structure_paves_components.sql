-- Estrutura os 11 pavês antigos conforme camadas e preparos descritos no receituário original em espanhol.
-- O Pavê Floresta Negra já estruturado fica intocado.
begin;

insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Cremes branco e de chocolate', 1, 1, 3, 3
from public.recipes rec
where rec.slug='pave-de-chocolate' and rec.source_page_start=3
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate' and rec.source_page_start=3
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[1,2,3,4,5,6,10]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate' and rec.source_page_start=3
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[1,2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem e camadas', 1, 2, 3, 3
from public.recipes rec
where rec.slug='pave-de-chocolate' and rec.source_page_start=3
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate' and rec.source_page_start=3
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem' and ri.position = any(array[7,8,9]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate' and rec.source_page_start=3
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[3,4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme base', 1, 1, 5, 5
from public.recipes rec
where rec.slug='pave-de-chocolate-bis' and rec.source_page_start=5
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate-bis' and rec.source_page_start=5
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[1,2,3,4]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate-bis' and rec.source_page_start=5
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[1]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Camada de BIS', 1, 2, 5, 5
from public.recipes rec
where rec.slug='pave-de-chocolate-bis' and rec.source_page_start=5
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate-bis' and rec.source_page_start=5
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem' and ri.position = any(array[5]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate-bis' and rec.source_page_start=5
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura de merengue', 1, 3, 5, 5
from public.recipes rec
where rec.slug='pave-de-chocolate-bis' and rec.source_page_start=5
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate-bis' and rec.source_page_start=5
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura' and ri.position = any(array[6,7]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate-bis' and rec.source_page_start=5
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura' and rs.position = any(array[3,4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'base', 'Base de biscoito', 1, 1, 6, 6
from public.recipes rec
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='base' and ri.position = any(array[1,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='base' and rs.position = any(array[1]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme de limão', 1, 2, 6, 6
from public.recipes rec
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[2,3,4]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem e decoração', 1, 3, 6, 6
from public.recipes rec
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem' and ri.position = any(array[5]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Resfriamento', 1, 4, 6, 6
from public.recipes rec
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=4);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-limao' and rec.source_page_start=6
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme', 1, 1, 7, 7
from public.recipes rec
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[1,2,3,4,5]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[1]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura', 1, 2, 7, 7
from public.recipes rec
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura' and ri.position = any(array[7,8,9,10]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura' and rs.position = any(array[2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'massa', 'Pão de ló', 1, 3, 7, 7
from public.recipes rec
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='massa' and ri.position = any(array[11,12,13,14]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='massa' and rs.position = any(array[3,4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem', 1, 4, 7, 7
from public.recipes rec
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=4);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem' and ri.position = any(array[6,15]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-pessego' and rec.source_page_start=7
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[5,6]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'recheio', 'Abacaxi caramelizado', 1, 1, 9, 9
from public.recipes rec
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='recheio' and ri.position = any(array[1,2]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='recheio' and rs.position = any(array[1]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme', 1, 2, 9, 9
from public.recipes rec
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[3,4,7]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura de claras', 1, 3, 9, 9
from public.recipes rec
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura' and ri.position = any(array[5,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura' and rs.position = any(array[3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem e finalização', 1, 4, 9, 9
from public.recipes rec
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=4);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem' and ri.position = any(array[8]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-abacaxi' and rec.source_page_start=9
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[4,5]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme de maracujá', 1, 1, 10, 10
from public.recipes rec
where rec.slug='pave-de-maracuja-e-chocolate' and rec.source_page_start=10
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-maracuja-e-chocolate' and rec.source_page_start=10
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[1,2,3,7]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-maracuja-e-chocolate' and rec.source_page_start=10
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[1,2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Cobertura de chocolate', 1, 2, 10, 10
from public.recipes rec
where rec.slug='pave-de-maracuja-e-chocolate' and rec.source_page_start=10
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-maracuja-e-chocolate' and rec.source_page_start=10
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura' and ri.position = any(array[5,6,9]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-maracuja-e-chocolate' and rec.source_page_start=10
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura' and rs.position = any(array[3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem', 1, 3, 10, 10
from public.recipes rec
where rec.slug='pave-de-maracuja-e-chocolate' and rec.source_page_start=10
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-maracuja-e-chocolate' and rec.source_page_start=10
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem' and ri.position = any(array[4,8]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-maracuja-e-chocolate' and rec.source_page_start=10
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[4,5]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'base', 'Camada de uvas', 1, 1, 11, 11
from public.recipes rec
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='base' and ri.position = any(array[1,2]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='base' and rs.position = any(array[1]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme de baunilha', 1, 2, 11, 11
from public.recipes rec
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[3,4,5,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Trufa de chocolate', 1, 3, 11, 11
from public.recipes rec
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura' and ri.position = any(array[7,8]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura' and rs.position = any(array[3,4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Chantilly e decoração', 1, 4, 11, 11
from public.recipes rec
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=4);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='finalizacao' and ri.position = any(array[9,10,11]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-uva-chocolate-e-chantilly' and rec.source_page_start=11
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[5,6]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme de doce de leite', 1, 1, 13, 13
from public.recipes rec
where rec.slug='pave-de-amendoim' and rec.source_page_start=13
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-amendoim' and rec.source_page_start=13
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[2,3]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-amendoim' and rec.source_page_start=13
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[1]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem com biscoitos e amendoim', 1, 2, 13, 13
from public.recipes rec
where rec.slug='pave-de-amendoim' and rec.source_page_start=13
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-amendoim' and rec.source_page_start=13
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem' and ri.position = any(array[1,4]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-amendoim' and rec.source_page_start=13
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Resfriamento', 1, 3, 13, 13
from public.recipes rec
where rec.slug='pave-de-amendoim' and rec.source_page_start=13
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-amendoim' and rec.source_page_start=13
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme de ameixa', 1, 1, 14, 14
from public.recipes rec
where rec.slug='pave-de-ameixa' and rec.source_page_start=14
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-ameixa' and rec.source_page_start=14
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[1,2,3,4,5,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-ameixa' and rec.source_page_start=14
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[1]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem com biscoitos', 1, 2, 14, 14
from public.recipes rec
where rec.slug='pave-de-ameixa' and rec.source_page_start=14
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-ameixa' and rec.source_page_start=14
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem' and ri.position = any(array[7,8]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-ameixa' and rec.source_page_start=14
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'finalizacao', 'Resfriamento', 1, 3, 14, 14
from public.recipes rec
where rec.slug='pave-de-ameixa' and rec.source_page_start=14
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);


update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-ameixa' and rec.source_page_start=14
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='finalizacao' and rs.position = any(array[4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme de café e chocolate', 1, 1, 15, 15
from public.recipes rec
where rec.slug='pave-de-cafe' and rec.source_page_start=15
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-cafe' and rec.source_page_start=15
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[1,2,3,5,6]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-cafe' and rec.source_page_start=15
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[1]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'cobertura', 'Claras com creme de leite', 1, 2, 15, 15
from public.recipes rec
where rec.slug='pave-de-cafe' and rec.source_page_start=15
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-cafe' and rec.source_page_start=15
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='cobertura' and ri.position = any(array[7]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-cafe' and rec.source_page_start=15
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='cobertura' and rs.position = any(array[2]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem e finalização', 1, 3, 15, 15
from public.recipes rec
where rec.slug='pave-de-cafe' and rec.source_page_start=15
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=3);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-cafe' and rec.source_page_start=15
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem' and ri.position = any(array[4]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-cafe' and rec.source_page_start=15
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[3,4]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'creme', 'Creme de chocolate branco', 1, 1, 16, 16
from public.recipes rec
where rec.slug='pave-de-chocolate-branco' and rec.source_page_start=16
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=1);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate-branco' and rec.source_page_start=16
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='creme' and ri.position = any(array[1,2,3,4,5]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate-branco' and rec.source_page_start=16
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='creme' and rs.position = any(array[1,2,3]);


insert into public.recipe_components
  (recipe_id, role, title, multiplier, position, source_page_start, source_page_end)
select rec.id, 'montagem', 'Montagem e decoração', 1, 2, 16, 16
from public.recipes rec
where rec.slug='pave-de-chocolate-branco' and rec.source_page_start=16
  and not exists (select 1 from public.recipe_components existing where existing.recipe_id=rec.id and existing.position=2);

update public.recipe_ingredients ri
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate-branco' and rec.source_page_start=16
  and ri.recipe_id=rec.id and ri.component_id is null
  and rc.role='montagem' and ri.position = any(array[6,7]);

update public.recipe_steps rs
set component_id=rc.id, updated_at=now()
from public.recipes rec
join public.recipe_components rc on rc.recipe_id=rec.id
where rec.slug='pave-de-chocolate-branco' and rec.source_page_start=16
  and rs.recipe_id=rec.id and rs.component_id is null
  and rc.role='montagem' and rs.position = any(array[4,5]);

commit;
