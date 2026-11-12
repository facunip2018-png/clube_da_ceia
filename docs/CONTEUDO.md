# Conteúdo — como as receitas entram no app

## Princípios (seção 4 do escopo)

- Nada é inventado: sem receitas, quantidades, temperaturas, tempos ou instruções que não estejam no PDF.
- Medidas originais preservadas; nenhuma conversão automática de unidades.
- Campos duvidosos viram **pontos de revisão** para conferência humana.
- Tudo entra como rascunho/revisão. Publicar exige: ficha estruturada + pontos resolvidos + aprovação + permissão comercial confirmada (regra aplicada pelo banco).

## Situação de cada material

| Coleção | Documento | Situação |
| --- | --- | --- |
| Pavês | `receita-de-pave-floresta-negra-com-creme-danete-…pdf` | **Recebido e estruturado** (1 ficha, 3 partes, 12 ingredientes, 16 etapas, 2 temporizadores, 23 pontos de revisão). O PDF não traz declaração de licença: permissão **a confirmar**. |
| Pavês | `11-receta-de-pave-completo-y-revisado.pdf` | **Falta enviar.** 11 itens catalogados só pelo título. Original em espanhol: tradução seguirá para revisão. |
| Panetones & Chocotones | `Receitas 02 de panetones.pdf` | **Recebido por transcrição (páginas 8–115).** 25 fichas estruturadas em revisão: Panetone Tradicional, Chocotone Tradicional, Chocotone de Churros, Chocotone de Ninho e 21 fichas adicionais (Ferrero Rocher, Brigadeiro, Morango, Trufado de Maracujá, Trufado, Ovomaltine, Brigadeiro Gourmet, Nutella, Coco, Oreo, 2 Amores, Nozes, Doce de Leite com Ameixas, Laka, Cobertura Natalina, Dressed, Alpino, Kinder Bueno, Red Velvet com Limão, Infantil e no Pote). Páginas, rendimentos e pontos sinalizados precisam de conferência. A transcrição não substitui a revisão do PDF original. |
| Rabanadas Recheadas | `rabanadas-recheadas-d-amp-cc-2021.pdf` | **Falta enviar.** 10 itens (bases, calda, fritura e recheios) bloqueados em *aguardando permissão*. O montador usa combinações ainda não verificadas. |
| Tortas Doces | `tortas-doces.pdf` | **Falta enviar.** 15 itens catalogados só pelo título. |
| Manjar de Coco | — | Coleção criada, sem receitas. Aguardando PDF. |
| Pudins | — | Coleção criada, sem receitas. Aguardando PDF. |

Itens “catalogados” têm apenas título e página de referência (levantamento do MVP, a conferir no PDF).
Eles **não** têm ingredientes nem etapas e não podem ser aprovados nem publicados.

## Caminho de uma ficha

```
PDF original ─► content/recipes/<coleção>/<slug>.json ─► npm run content:build ─► supabase/seed.sql ─► banco
                (transcrição fiel + textos originais)     (validação + geração)      (carga idempotente)
                                                                                         │
                          painel admin: revisar pontos ─► aprovar ─► confirmar permissão ─► publicar
```

1. **Transcrição** — a ficha é escrita em JSON seguindo o modelo de
   `content/recipes/paves/pave-floresta-negra-com-creme-danete.json`: partes (creme, massa, recheio, cobertura,
   calda, montagem…), ingredientes com quantidade, unidade e **texto original**, etapas com texto original,
   temporizadores com o trecho que os justifica, dicas, observações, utensílios, páginas de origem e pontos de revisão.
2. **Validação** — `npm run content:build` recusa: páginas fora do documento, ingrediente sem texto original,
   temporizador sem trecho de origem, conteúdo marcado como aprovado/publicado ou permissão marcada como confirmada.
3. **Carga** — execute o `supabase/seed.sql` gerado no SQL Editor. Ele só acrescenta o que é novo; um item
   que era apenas “catalogado” recebe a ficha; nada editado no painel é sobrescrito.
4. **Revisão e publicação** — no painel, em **Receitas**.

## Regras de modelagem

- **Receita / componente / variação** — receita completa; componente compartilhado (massa, esponja, calda,
  recheio, cobertura); variação combinável (ex.: recheios de rabanada). Os indicadores do app contam cada tipo separadamente, a partir dos registros publicados.
- **Componentes compartilhados** — uma parte de receita pode apontar para outra ficha (`linked_recipe_id`),
  com multiplicador. A receita só publica se o componente também estiver publicado.
- **Rabanadas** — o montador só oferece pares registrados em `recipe_compatibilities`. Os pares atuais
  (doce com doce, salgado com salgado) foram inferidos dos títulos e estão marcados como **não verificados**.
- **Ajuste de porções** — `linear` multiplica; `manual` multiplica e pede validação (ex.: “1 pacote”);
  `fixed` não muda. Sem quantidade numérica, a medida textual (“a gosto”, “quantidade não informada”) é mantida.
- **Porções** — quando o material não informa quantas pessoas a receita serve, o campo fica vazio e o
  ajuste é feito pelo rendimento original (ex.: travessas). O app não estima.

## Cuidados

- **Arquive, não exclua.** Se uma receita for apagada do banco, a próxima carga a recria a partir de `content/`.
- **PDFs nunca vão para o repositório nem para pastas públicas.** Envie pelo painel (Documentos), que grava no bucket privado `source-documents`.
- **Imagens de capa** são ilustrativas (geradas por IA). Para usar fotos próprias, envie ao bucket `recipe-images` e informe a URL no campo “Imagem de capa”.
