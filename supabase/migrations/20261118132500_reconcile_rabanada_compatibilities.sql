-- Corrige as bases das seis combinações confirmadas no PDF de Rabanadas Recheadas.
-- Preserva os registros e IDs das compatibilidades: apenas troca a referência da base
-- (orientação das páginas 3/4) pela ficha real de massa (páginas 8/9).
-- Cada página de origem abaixo contém o recheio correspondente e identifica a versão doce/salgada.
with expected (
  legacy_base_slug,
  base_slug,
  filling_slug,
  source_page,
  note
) as (
  values
    (
      'pao-para-rabanada-doce',
      'massa-pao-rabanada-doce',
      'rabanada-doce-recheada-com-nutella',
      14,
      'Base: massa de pão para rabanada doce (página 8); recheio Nutella e finalização com açúcar e canela (página 14). Correspondência conferida no texto extraído do PDF.'
    ),
    (
      'pao-para-rabanada-doce',
      'massa-pao-rabanada-doce',
      'rabanada-doce-recheada-com-doce-de-leite',
      15,
      'Base: massa de pão para rabanada doce (página 8); recheio de doce de leite e finalização com açúcar e canela (página 15). Correspondência conferida no texto extraído do PDF.'
    ),
    (
      'pao-para-rabanada-doce',
      'massa-pao-rabanada-doce',
      'rabanada-doce-com-brigadeiro-de-nozes',
      16,
      'Base: massa de pão para rabanada doce (página 8); brigadeiro de nozes e finalização com açúcar e canela (página 16). Correspondência conferida no texto extraído do PDF.'
    ),
    (
      'pao-para-rabanada-salgada',
      'massa-pao-rabanada-salgada',
      'rabanada-salgada-com-gorgonzola-nozes-e-damasco',
      18,
      'Base: massa de pão para rabanada salgada (página 9); creme de gorgonzola, nozes e damasco (página 18), identificado como rabanada salgada. Correspondência conferida no texto extraído do PDF.'
    ),
    (
      'pao-para-rabanada-salgada',
      'massa-pao-rabanada-salgada',
      'rabanada-salgada-com-salame-e-ricota',
      20,
      'Base: massa de pão para rabanada salgada (página 9); creme de salame e ricota (página 20), identificado como rabanada salgada. Correspondência conferida no texto extraído do PDF.'
    ),
    (
      'pao-para-rabanada-salgada',
      'massa-pao-rabanada-salgada',
      'rabanada-salgada-com-peito-de-peru-e-queijo',
      22,
      'Base: massa de pão para rabanada salgada (página 9); creme de peito de peru com queijo (página 22), identificado como rabanada salgada. Correspondência conferida no texto extraído do PDF.'
    )
),
matched as (
  select
    compatibility.id as compatibility_id,
    actual_base.id as actual_base_id,
    expected.source_page,
    expected.note
  from expected
  join public.recipes legacy_base
    on legacy_base.slug = expected.legacy_base_slug
   and legacy_base.kind = 'component'
   and legacy_base.component_role = 'base'
  join public.recipes actual_base
    on actual_base.slug = expected.base_slug
   and actual_base.kind = 'component'
   and actual_base.component_role = 'base'
  join public.recipes filling
    on filling.slug = expected.filling_slug
   and filling.kind = 'variation'
  join public.recipe_compatibilities compatibility
    on compatibility.recipe_id = legacy_base.id
   and compatibility.compatible_recipe_id = filling.id
   and compatibility.relation = 'recheio'
)
update public.recipe_compatibilities compatibility
set recipe_id = matched.actual_base_id,
    source_page = matched.source_page,
    verified = true,
    note = matched.note
from matched
where compatibility.id = matched.compatibility_id
  and (
    compatibility.recipe_id,
    compatibility.source_page,
    compatibility.verified,
    compatibility.note
  ) is distinct from (
    matched.actual_base_id,
    matched.source_page,
    true,
    matched.note
  );
