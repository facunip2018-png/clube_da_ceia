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
cp .env.example .env.local        # depois edite: NEXT_PUBLIC_DEMO_MODE=true para experimentar sem Supabase
npm run dev                       # http://localhost:3000
```

Outros comandos:

```bash
npm run typecheck      # verificação de tipos
npm test               # 87 testes (regras de negócio + banco de dados)
npm run content:build  # valida content/ e gera supabase/seed.sql, setup_completo.sql e os dados da demonstração
npm run content:check  # confere se os arquivos gerados estão em dia
npm run db:conferir    # gera o SQL que confere o banco do Supabase contra este repositório
npm run test:hosted    # teste de fumaça contra o Supabase real (contas de teste; ver docs/TESTES.md)
npm run build && npm start
```

## Colocar no ar

Passo a passo completo em **[docs/CONFIGURACAO.md](docs/CONFIGURACAO.md)** (Supabase → GitHub → Vercel →
primeiro administrador → Mercado Pago → OpenAI).

## Documentação

- [docs/CONFIGURACAO.md](docs/CONFIGURACAO.md) — configuração de Supabase, GitHub, Vercel, Mercado Pago e OpenAI
- [docs/CONTEUDO.md](docs/CONTEUDO.md) — como as receitas entram no app e o que falta de cada PDF
- [docs/TESTES.md](docs/TESTES.md) — o que foi testado, como repetir e o que ainda depende de credenciais
- [docs/RELATORIO-FASES.md](docs/RELATORIO-FASES.md) — situação de cada uma das 8 fases do projeto

## Estrutura

```
content/                 Fonte do conteúdo (coleções, documentos, catálogo, fichas estruturadas)
scripts/content-build.mjs  Valida o conteúdo e gera a carga do banco
supabase/migrations/     Estrutura, funções, segurança (RLS) e Storage
supabase/seed.sql        Carga de conteúdo (gerada, idempotente)
supabase/setup_completo.sql  Tudo em um arquivo, para colar no SQL Editor
src/lib/                 Regras de negócio puras (porções, compras, cronograma, temporizadores, Chef, pagamentos)
src/data/                Acesso a dados: Supabase (produção) e armazenamento local (demonstração)
src/server/              Código que só roda no servidor (chaves privadas)
src/app/                 Telas e rotas de API
tests/                   Testes unitários, de banco e de ponta a ponta
```

## Segurança, em resumo

- RLS ligado nas 31 tabelas; cada pessoa só enxerga os próprios planos, listas, favoritos, sessões e conversas.
- Ficha completa (ingredientes, etapas, tempos) só é lida por quem tem acesso válido à temporada **e** apenas de receitas publicadas.
- Papel de administrador fica no banco e não pode ser alterado pela própria pessoa; `/admin` é protegido no servidor.
- Chaves da OpenAI, do Mercado Pago e a `service_role` do Supabase existem somente no servidor.
- O acesso pago é liberado exclusivamente pelo webhook assinado, após consulta do pagamento na API do Mercado Pago; o processamento é idempotente.
- PDFs originais ficam em bucket privado, acessível só a administradores.
- O service worker guarda apenas arquivos estáticos: conteúdo premium não fica disponível offline.

## Imagens

As fotos de capa em `public/images/` são **ilustrações geradas por IA** para a identidade do app; não foram
extraídas dos e-books. Cada receita pode receber outra imagem pelo painel (campo “Imagem de capa”).
