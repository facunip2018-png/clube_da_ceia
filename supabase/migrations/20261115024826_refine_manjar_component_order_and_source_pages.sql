-- Corrige a ordem de componentes e referências de páginas do PDF de manjares.
begin;
update public.recipes set source_page_start=2,source_page_end=3,updated_at=now()
where slug='manjar-com-calda-de-chocolate';
update public.recipes set source_page_start=8,source_page_end=9,updated_at=now()
where slug='manjar-ouro-branco';
update public.recipe_components c set position=case c.role when 'calda' then 1 when 'massa' then 2 else c.position end,updated_at=now()
from public.recipes r where c.recipe_id=r.id and r.slug in ('manjar-de-doce-de-leite-e-ameixa','manjar-ouro-branco');
insert into public.recipe_components(recipe_id,role,title,multiplier,position,source_page_start,source_page_end)
select r.id,'finalizacao','Finalização',1,3,r.source_page_start,r.source_page_end
from public.recipes r
where r.slug in ('manjar-de-milho-com-calda-de-canela','manjar-branco-especial','manjar-de-nutella')
and not exists(select 1 from public.recipe_components c where c.recipe_id=r.id and c.role='finalizacao');
update public.recipe_steps s set component_id=final.id,position=1,updated_at=now()
from public.recipes r
join public.recipe_components old on old.recipe_id=r.id and old.role='calda'
join public.recipe_components final on final.recipe_id=r.id and final.role='finalizacao'
where s.recipe_id=r.id and s.component_id=old.id and
 ((r.slug='manjar-de-milho-com-calda-de-canela' and s.position=3)
  or (r.slug='manjar-branco-especial' and s.position=3)
  or (r.slug='manjar-de-nutella' and s.position=1));
commit;