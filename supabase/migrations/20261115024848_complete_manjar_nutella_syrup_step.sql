-- Separa a mistura da calda da etapa de desenformar o Manjar de Nutella.
begin;
update public.recipe_steps
set instruction='Desenforme, regue com a calda e sirva.',
    original_text='Desenforme, regue com os ingredientes da calda misturados e sirva.',
    position=1,updated_at=now()
where recipe_id=(select id from public.recipes where slug='manjar-de-nutella')
  and component_id=(select c.id from public.recipe_components c join public.recipes r on r.id=c.recipe_id where r.slug='manjar-de-nutella' and c.role='finalizacao');
insert into public.recipe_steps(recipe_id,component_id,position,instruction,original_text)
select r.id,c.id,1,'Misture a Nutella® com o creme de leite.','Misture os ingredientes da calda.'
from public.recipes r join public.recipe_components c on c.recipe_id=r.id and c.role='calda'
where r.slug='manjar-de-nutella'
and not exists(select 1 from public.recipe_steps s where s.component_id=c.id);
commit;