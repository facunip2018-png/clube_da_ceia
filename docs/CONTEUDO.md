# Conteúdo — inventário e regras operacionais

**Última conferência do banco:** 17/11/2026  
**Fonte de verdade:** projeto Supabase `nnfpsayxjwyqnixmmzhl`. Este documento descreve o estado observado no banco; não substitui a conferência do PDF quando a extração está ausente ou incompleta.

## Princípios editoriais

- Não inventar receitas, ingredientes, quantidades, unidades, temperaturas, tempos ou instruções.
- Preservar o texto original e a página de origem de cada ingrediente e etapa.
- Quando a divisão entre partes não estiver demonstrada pelo material, manter o conteúdo sem reatribuição e registrar a pendência.
- Não excluir registros para corrigir conteúdo: preferir ajustes aditivos e versionados.
- PDFs permanecem no bucket privado `source-documents`; não devem ser commitados no GitHub nem colocados em pastas públicas.
- Não considerar a permissão comercial comprovada apenas porque o campo está marcado como `confirmed`: manter a observação documental que sustenta essa confirmação.

## Inventário observado no Supabase

| Coleção | Fonte no Supabase | Fichas | Componentes | Ingredientes | Etapas |
| --- | --- | ---: | ---: | ---: | ---: |
| Tortas Doces | PDF armazenado; 19/19 páginas extraídas | 15 | 45 | 146 | 80 |
| Pudins | PDF armazenado; 36/36 páginas extraídas | 13 | 40 | 83 | 77 |
| Pavês | Recetario Gourmet: 16/16 páginas; Pavê Floresta Negra: arquivo recebido, sem caminho no Storage e sem páginas extraídas | 12 | 38 | 104 | 66 |
| Manjar de Coco | PDF armazenado; 9/9 páginas extraídas | 9 | 26 | 89 | 64 |
| Panetones & Chocotones | PDF armazenado; contagem de páginas não cadastrada e 0 páginas extraídas | 25 | 95 | 446 | 433 |
| Rabanadas Recheadas | PDF armazenado; 25/25 páginas extraídas | 12 componentes + 9 variações | 39 | 62 | 67 |

### Integridade das fichas compostas prioritárias

Nas tortas, pudins e pavês, a conferência encontrou:

- 0 ingredientes sem componente;
- 0 etapas sem componente;
- 0 componentes órfãos;
- 0 vínculos de ingrediente ou etapa apontando para componente de outra receita ou inexistente;
- 0 posições duplicadas em componentes, ingredientes ou etapas.

A Torta de Chocolate continua com **Massa, Recheio e Cobertura**, 7 ingredientes e 4 etapas. A migração versionada correspondente já existe em `supabase/migrations/20261114020000_structure_torta_de_chocolate.sql`; não reaplicar essa migração para tentar corrigir o histórico.

### Observações por coleção

- **Tortas:** as divisões explícitas da apostila (por exemplo, massa, recheio e cobertura) foram modeladas. Onde o texto usa apenas uma lista de ingredientes, a divisão depende da sequência de preparo; não criar novas partes sem evidência.
- **Pudins:** a apostila contém um capítulo próprio de caldas e coberturas. As fichas mantêm as referências a essas preparações e as partes de massa, calda, ganache, cobertura, cocção e finalização conforme o texto disponível.
- **Pavês:** 11 fichas vêm do Recetario Gourmet em espanhol. A ficha Pavê Floresta Negra com Creme Danete mantém 3 componentes, 12 ingredientes e 16 etapas, mas sua fonte está apenas como recebida: sem arquivo no Storage e sem páginas extraídas. Há 11 observações editoriais informativas abertas; não reprocessar nem alterar essa ficha sem recuperar a fonte.
- **Manjar:** a fonte já está armazenada e as 9 páginas estão extraídas; as 9 fichas já estão estruturadas. Não repetir a importação.
- **Panetones:** as 25 fichas têm 95 componentes, 446 ingredientes e 433 etapas. Não há ingrediente ou etapa sem componente e os campos `needs_review` de ingredientes e etapas estão zerados. Como o PDF ainda não tem páginas extraídas no Supabase, a correspondência página a página continua pendente; preservar as fichas existentes.
- **Rabanadas:** os 6 pares da tabela `recipe_compatibilities` continuam não verificados. Os vínculos usam como bases os registros “Escolha e armazenamento do pão” e “Corte, congelamento e descongelamento do pão”, com referências às páginas 3 e 4; porém, a extração atual dessas páginas mostra a capa e a apresentação dos autores. As massas efetivas doce e salgada estão em registros separados, nas páginas 8 e 9. O componente `RabanadaBuilder` também monta a lista “Preparos da base” com todos os componentes compartilhados da coleção, sem restringi-los à base selecionada. Há ainda 3 registros de variação (chocolate, pistache e leite Ninho) sem pares na tabela de compatibilidade, com referências de página que não correspondem claramente ao texto extraído. Não alterar esses vínculos nem liberar novas combinações até reconciliar as páginas e a composição do montador com a fonte.

## Publicação: limitação atual da proteção no banco

A função `public.guard_recipe_status()` atualmente impede a publicação quando `content_state` não é `structured` e preenche `published_at`. Ela **não** verifica diretamente a existência de ingredientes e etapas, flags editoriais abertas ou permissão comercial. Portanto, não documentar essas verificações como se já fossem garantidas pelo trigger. A proteção precisa ser fortalecida e testada em uma alteração própria, sem mexer em autenticação, assinatura, RLS ou Storage.

## Caminho de manutenção

1. Conferir o documento original e as páginas extraídas no Supabase.
2. Associar ingredientes e etapas a componentes apenas quando a correspondência estiver sustentada pelo texto e pela sequência de preparo.
3. Registrar cada alteração de banco em migração versionada, idempotente e revisada no GitHub.
4. Validar contagens, vínculos, órfãos e posições duplicadas depois da migração.
5. Executar os testes automatizados de ficha, porções, compras e modo cozinheiro antes de qualquer alteração de código chegar à produção.

## Migrações e histórico

Os arquivos de estruturação de tortas estão versionados no repositório. O histórico remoto do Supabase, porém, contém duas versões registradas para `structure_torta_de_chocolate` e duas para `structure_tortas_components`, com identificadores diferentes dos nomes dos arquivos locais. Não reaplicar essas migrações nem editar diretamente o histórico remoto; reconciliar a divergência em procedimento separado e documentado.

## Compatibilidade da experiência

- `src/lib/recipe-view.ts` preserva ingredientes e etapas antigos com `component_id = null` em uma parte “Preparo principal”.
- A calculadora e a lista de compras percorrem as partes montadas da ficha, sem exigir que toda receita antiga tenha componentes.
- O modo cozinheiro usa a sequência de etapas da ficha montada.
- Os testes unitários de ficha, escala e lista de compras ficam em `tests/unit/`. A existência desses testes não significa que tenham sido executados em cada alteração; registrar apenas execuções efetivamente realizadas.

## Cuidados

- Arquive, não exclua.
- Não sobrescreva conteúdo editado no painel com nova carga de seed.
- Não exponha caminhos internos do Storage nem mova PDFs para o repositório.
- Não publique fichas incompletas ou com fonte/divisão ainda não confirmada.
