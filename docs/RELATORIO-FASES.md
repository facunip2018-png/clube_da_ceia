# Relatório por fase

Situação em 10/11/2026. Legenda: ✅ feito e testado · 🟡 feito, aguardando credenciais ou conteúdo para testar/concluir · ⬜ pendente.

## Fase 1 — Evolução da interface, coleções e receitas ✅

**Implementado**
- Identidade do MVP preservada e evoluída (cores, tipografia, sidebar, topbar, hero, cards), com escala de leitura maior, foco acessível, animações suaves e estados de carregamento, vazio e erro.
- Navegação: lateral no desktop, inferior no celular (Início, Coleções, Minha ceia, Chef IA, Perfil).
- Todas as telas do MVP mantidas: Início, Coleções, Coleção (busca + ordem do material/alfabética), Receita, Minha ceia, Lista de compras, Chef, Desafios, Temporizador, Perfil e Painel admin.
- 6 coleções; contagens calculadas dos registros reais e da situação de publicação (receitas, componentes e variações contados separadamente; “em curadoria” e “em breve” quando não há publicadas).
- PWA: manifesto, ícones, tela de abertura, service worker (somente arquivos estáticos), página offline.

**Arquivos**: `src/app/globals.css`, `src/app/layout.tsx`, `src/components/*`, `src/app/(app)/**`, `src/app/manifest.ts`, `public/sw.js`, `public/icons/*`, `public/images/*`.

**Pendências**: fotos de capa são ilustrações geradas por IA (substituíveis pelo painel).

## Fase 2 — Banco de dados, autenticação e permissões ✅ (falta só o cadastro por e-mail em produção)

**Implementado**
- 31 tabelas: as 26 do escopo + `recipe_step_ingredients`, `recipe_notes`, `recipe_compatibilities`, `review_flags`, `plan_tasks`.
- RLS em todas; papéis `customer`/`admin` no banco; `/admin` protegido no servidor (`src/proxy.ts`); auditoria gravada por gatilhos.
- Login, cadastro, recuperação e redefinição de senha, perfil (Supabase Auth).

**Tabelas**: seasons, profiles, collections, source_documents, recipes, recipe_components, ingredients, recipe_ingredients, recipe_steps, recipe_step_ingredients, recipe_step_timers, recipe_notes, recipe_tags, recipe_compatibilities, review_flags, recipe_favorites, meal_plans, plan_recipes, plan_tasks, shopping_lists, shopping_items, cooking_sessions, challenges, user_challenges, challenge_submissions, ai_conversations, ai_messages, orders, payment_transactions, memberships, admin_audit_logs.

**Arquivos**: `supabase/migrations/*`, `supabase/seed.sql`, `supabase/setup_completo.sql`, `src/data/*`, `src/server/supabase.ts`, `src/proxy.ts`, `src/app/(auth)/**`, `src/app/auth/**`.

**Testes**: 35 testes de banco em PostgreSQL real (PGlite).

**Atualização de 11/11/2026 — instalado e testado no Supabase real**
- *Implementado*: banco instalado no projeto `clube_da_ceia_perfeita` pelo conector (5 migrations registradas no
  histórico + carga do catálogo); ferramenta de conferência (`npm run db:conferir`); teste de fumaça da API
  (`npm run test:hosted`); fluxo no navegador em modo Supabase (`tests/e2e/fluxo_supabase.py`).
- *Arquivos*: `supabase/migrations/*` (renomeadas para os números de versão do histórico do Supabase),
  nova `20261111180506_storage_capas_select.sql`, `src/data/supabase-store.ts`, `src/app/api/chef/route.ts`,
  `src/components/auth-form.tsx`, `tests/db/conferencia-hospedado.test.ts`, `tests/hosted/smoke.mjs`,
  `tests/e2e/fluxo_supabase.py`, `package.json`, `.gitignore`, `docs/*`.
- *Tabelas criadas no projeto*: as 31 da lista acima, 19 funções, 37 gatilhos, 59 policies + 8 de Storage, 3 buckets.
- *Integrações funcionando (testadas)*: Supabase Auth com e-mail e senha, API de dados com RLS, funções RPC,
  Storage, sessão por cookies no Next.js e proteção do `/admin` no servidor.
- *Testes*: 28/28 na conferência do banco, 56/56 na API, 26/26 no navegador; três defeitos encontrados e
  corrigidos (detalhes em [TESTES.md](TESTES.md)).
- *Pendências*: Site URL, Redirect URLs e modelos de e-mail (dependem do endereço da Vercel); cadastro com
  confirmação por e-mail e recuperação de senha ainda **não testados** de ponta a ponta; SMTP próprio antes de
  abrir as vendas; primeiro administrador; envio do código ao GitHub (falta credencial) e deploy na Vercel.

## Fase 3 — Importação dos PDFs e revisão administrativa 🟡

**Implementado**
- Fluxo `draft → review → approved → published` (+ `pending_permission`, `archived`) aplicado pelo banco.
- Painel: lista com filtros, editor de revisão com texto original ao lado de cada ingrediente e etapa, pontos de revisão, requisitos de publicação, documentos com permissão comercial e envio do PDF ao bucket privado, auditoria.
- Importação por arquivo de conteúdo validado (`content/` → `npm run content:build` → `seed.sql`).

**Pendências**: importação assistida pelo próprio painel (extrair o texto do PDF na tela e gerar o rascunho) ainda não existe — hoje a estruturação é feita no arquivo de conteúdo. Envio de PDF pelo painel não foi testado contra o Storage real.

## Fase 4 — Catálogo completo e fichas 🟡

**Implementado**: 62 itens catalogados; ficha completa do **Pavê Floresta Negra com Creme Danete**.

**Pendências**: 5 PDFs (ver [CONTEUDO.md](CONTEUDO.md)). Cada um vira fichas no mesmo modelo, sem alteração de código.

## Fase 5 — Planejador, calculadora, lista de compras e modo cozinheiro ✅

**Implementado**
- Calculadora a partir do rendimento original; medidas textuais preservadas; itens sem conversão possível sinalizados.
- Planejador: ocasião, data, horário, convidados, nome, cardápio, cronograma de trás para frente (só tempos das fichas + bloco de organização ajustável), checklist.
- Lista: soma apenas mesma unidade, edição, itens manuais, categorias, marcar comprado, compartilhar, salva por pessoa.
- Modo cozinheiro: uma etapa por vez, progresso, ingredientes da etapa, texto ampliado, tela sempre acesa, retomada; temporizadores múltiplos que continuam ao trocar de tela, com aviso sonoro e notificação.

**Testes**: unitários + ponta a ponta no navegador.

## Fase 6 — Chef IA e desafios 🟡

**Implementado**
- Chef em rota de servidor, restrito a quem tem acesso, com limite diário, histórico por pessoa e base exclusiva nas fichas publicadas; instruções para não inventar e para sinalizar substituições.
- Sem chave da OpenAI, responde por consulta direta à ficha (identificado na tela como “sem IA generativa”).
- 9 desafios com pontos, medalhas e progresso calculado no banco; envio opcional de foto para bucket privado.

**Pendências**: chamada à OpenAI não executada (falta a chave); envio de foto não testado contra o Storage real.

## Fase 7 — Mercado Pago e temporadas 🟡

**Implementado**
- Temporadas configuráveis no painel (preço, vendas, acesso, situação); acesso válido só dentro do período.
- Checkout Pro: pedido com preço do banco → preferência → retorno informativo → webhook assinado → consulta à API → `process_payment_event` (idempotente; confere valor e moeda; trata aprovado, pendente, recusado, cancelado, reembolso, estorno e disputa).
- Cortesias, revogação e bloqueio manual pelo painel.

**Pendências**: desligado por padrão (`PAYMENTS_ENABLED=false`). Falta testar com credenciais de teste do Mercado Pago. **Preço e datas da temporada são marcadores**: defina no painel.

## Fase 8 — Testes, segurança, correções e publicação 🟡

**Feito**: 87 testes automatizados, 49 verificações de ponta a ponta, verificações de segurança do build de produção (ver [TESTES.md](TESTES.md)).

**Pendências**: deploy na Vercel; testes com serviços reais; revisão das permissões comerciais de cada material; política de segurança de conteúdo (CSP) mais restritiva.

## Decisões que dependem de você

1. **Permissão comercial** de cada material — o PDF do Pavê não traz declaração de licença; o das rabanadas, segundo o levantamento do MVP, restringe reprodução e uso comercial.
2. **Preço e datas** da temporada.
3. **Porções** — o Pavê informa apenas “1 travessa de 27 × 17 cm”. Se quiser informar um número de porções, isso é uma decisão editorial sua, registrada no painel.
4. **Fotos** — manter as ilustrações ou enviar fotos próprias.
