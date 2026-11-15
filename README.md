# Clube da Ceia Perfeita — Natal & Ano-Novo

Aplicativo web (PWA) de receitas para a temporada de festas: coleções gastronômicas, fichas completas,
calculadora de porções, planejador da ceia, lista de compras inteligente, modo cozinheiro com
temporizadores, Chef IA, desafios e painel administrativo com fluxo de curadoria.

É a evolução do MVP em HTML (`clube_da_ceia_perfeita_mvp_v2.html`): mesma identidade visual
(verde-floresta `#173D2C`, dourado `#C5A15B`, fundo `#FAF9F5`, Playfair Display + Inter), mesma
estrutura de navegação e as mesmas telas — agora com dados reais, login, permissões e banco de dados.

> **Regra de ouro do conteúdo:** nada é inventado. Ingredientes, quantidades, tempos e etapas vêm
> exclusivamente dos PDFs originais, entram como rascunho e só são publicados depois de revisão
> humana **e** de confirmada a permissão comercial do material.

> **Mantenha o repositório privado.** As pastas `content/`, `supabase/seed.sql` e `src/server/` contêm o texto das
> receitas dos e-books. Em um repositório público esse conteúdo ficaria exposto.

## Tecnologias

| Camada | Escolha |
| --- | --- |
| Aplicação | Next.js 16 (App Router) + React 19 + TypeScript |
| Banco, login e arquivos | Supabase (PostgreSQL com RLS, Auth, Storage) |
| Hospedagem | Vercel |
| Pagamento | Mercado Pago — Checkout Pro (pagamento único por temporada) |
| IA | OpenAI (Responses API), somente no servidor |
| Testes | Vitest + PGlite (PostgreSQL real em WebAssembly) + Playwright (ponta a ponta) |

## Como o app decide o modo de funcionamento

| Situação | Modo | O que acontece |
| --- | --- | --- |
| Chaves do Supabase definidas | **produção** | Login real, dados no Supabase, permissões pelo RLS |
| Sem Supabase e `NEXT_PUBLIC_DEMO_MODE=true` | **demonstração** | Tudo funciona no navegador, sem servidor. Barra “Demonstração” troca entre Administradora, Cliente e Visitante |
| Nada configurado | **configuração** | Tela explicando o que falta. Nenhum conteúdo é exibido |

⚠️ **Nunca ative o modo demonstração em produção**: ele entrega o catálogo de exemplo (inclusive
fichas não publicadas) a qualquer visitante. Ele é ignorado automaticamente quando o Supabase está configurado.

## Rodar no computador

```bash
npm install
cp .env.example .env.local
npm run dev
```

Outros comandos:

```bash
npm run typecheck
npm test
npm run content:build
npm run content:check
npm run db:conferir
npm run test:hosted
npm run build && npm start
```

## Colocar no ar

Passo a passo técnico em **[docs/CONFIGURACAO.md](docs/CONFIGURACAO.md)**.

## Documentação

- [Manual do cliente](docs/MANUAL-CLIENTE.md) — como entrar, encontrar receitas, montar a ceia, usar a lista, favoritas, Chef, calculadora e modo cozinheiro.
- [Manual do administrador](docs/MANUAL-ADMINISTRADOR.md) — operação do painel, cadastro e publicação de receitas, pagamentos/webhook, Gumlet, segurança e pendências.
- [Configuração técnica](docs/CONFIGURACAO.md) — configuração de Supabase, GitHub, Vercel, Mercado Pago e serviços.
- [Conteúdo](docs/CONTEUDO.md) — como as receitas entram no app.
- [Testes](docs/TESTES.md) — o que foi testado e o que ainda depende de credenciais.
- [Relatório por fases](docs/RELATORIO-FASES.md) — situação histórica das fases do projeto.

> **Nota de manutenção:** os manuais de cliente e administrador são a referência operacional atual deste conjunto. Alguns documentos técnicos históricos podem conter estados antigos do catálogo; confira o painel e o Supabase para a situação atual.

## Estrutura

```
content/                    Fonte do conteúdo (coleções, documentos e fichas estruturadas)
scripts/content-build.mjs   Valida o conteúdo e gera a carga do banco
supabase/migrations/        Estrutura, funções, segurança (RLS) e Storage
supabase/seed.sql           Carga de conteúdo (gerada, idempotente)
src/lib/                    Regras de negócio puras
src/data/                   Acesso a dados: Supabase e armazenamento local de demonstração
src/server/                 Código que só roda no servidor (chaves privadas)
src/app/                    Telas e rotas de API
tests/                      Testes unitários, de banco e de ponta a ponta
```

## Segurança, em resumo

- RLS nas tabelas; cada pessoa só enxerga seus próprios planos, listas, favoritos, sessões e conversas.
- Ficha completa só é lida por quem tem acesso válido à temporada e apenas para receitas publicadas.
- Papel de administrador fica no banco e não pode ser alterado pela própria pessoa; painel protegido no servidor.
- Chaves privadas existem somente no servidor.
- O acesso pago é liberado pelo webhook validado, após consulta do pagamento na API do Mercado Pago; o processamento é idempotente.
- PDFs originais ficam em bucket privado.
- O service worker guarda apenas arquivos estáticos: conteúdo premium não fica disponível offline.
