# Testes

## Como rodar

```bash
npm run typecheck   # tipos
npm test            # 87 testes: regras de negócio (52) + banco de dados (35)
npm run content:check
```

Os testes de banco não precisam de Docker nem de internet: usam o **PGlite** (PostgreSQL real compilado
para WebAssembly), aplicam as migrations e a carga exatamente como serão executadas no Supabase e
simulam as chamadas da API com as roles `anon`, `authenticated` e `service_role`.

## O que está coberto

### Banco de dados (`tests/db`, 35 testes)

- Estrutura: 31 tabelas, todas com RLS ligado; `setup_completo.sql` equivale a migrations + seed.
- Carga: 62 itens, 1 ficha estruturada, quantidades originais do Pavê preservadas; carga idempotente que não sobrescreve ajustes do painel.
- Fluxo editorial: não aprova com pontos de revisão em aberto nem sem ficha; não publica sem aprovação nem sem permissão comercial; retirada da permissão tira a receita do ar; tudo registrado em auditoria.
- Conteúdo premium: visitante e cliente sem acesso não leem ingredientes, etapas, dicas ou temporizadores; temporada em rascunho ou fora do período não libera acesso.
- Dados pessoais: planos, listas, favoritos e sessões invisíveis para outras pessoas (inclusive para a administração).
- Papéis: cliente não consegue se promover; promoção só pela função protegida, com auditoria.
- Desafios: progresso calculado no servidor; conquistas não são perdidas; fotos só na pasta da própria pessoa.
- Chef IA: histórico por pessoa, sem edição nem exclusão de mensagens (base do limite de uso).
- Pagamentos: navegador não cria pedido nem concede acesso; pendente não libera; valor ou moeda divergente não libera; aprovado libera uma única vez mesmo com webhooks repetidos; disputa mantém; estorno revoga; bloqueio manual prevalece.
- Storage: PDFs originais só para administradores; imagens públicas só com escrita de administradores.

### Regras de negócio (`tests/unit`, 52 testes)

- Formatação pt-BR, frações e plurais; calculadora de porções (sem conversão de unidades, medidas textuais preservadas, validação sinalizada).
- Lista de compras: soma só mesmo ingrediente + mesma unidade; repetir a receita não duplica; remover desfaz só a parte dela.
- Cronograma: cálculo de trás para frente apenas com tempos da ficha; sem horários inventados.
- Temporizadores: continuam corretos com a tela fechada; pausa, retomada, reinício.
- Desafios: mesma regra da função do banco.
- Chef IA: contexto enviado ao modelo; resposta “não consta na ficha”; aviso de substituição; recusa de calcular por pessoas sem dado de porções; pergunta fora do assunto da receita aberta.
- Mercado Pago: manifesto e assinatura HMAC conforme a documentação; rejeição de qualquer alteração; conversão de valores; janela de vendas.
- Modo demonstração: as mesmas regras do banco reproduzidas no armazenamento local.

### Ponta a ponta no navegador (`tests/e2e/`, 49 + 17 verificações)

Executado com Chromium (Playwright) contra o build de produção em modo demonstração, em 1440×900 e 390×844:
administradora revisa, aprova, confirma permissão, publica e ativa a temporada; cliente usa calculadora,
lista, planejador (cronograma 12:26 / 13:00 / 20:00), modo cozinheiro (retomada na etapa certa, temporizador
que continua fora da tela), desafios e Chef; visitante encontra os bloqueios; nenhuma tela de celular com
rolagem lateral; zero erros no console.

`fluxo_admin.py` complementa com: busca global, montador de rabanadas (base salgada só oferece recheios salgados),
edição de ingrediente e de dados gerais no painel, coleções, revogação e concessão de acesso, bloqueio da compra
para acesso suspenso e reinício da demonstração.

### Verificações do build de produção (com chaves fictícias)

| Verificação | Resultado |
| --- | --- |
| `/api/demo/catalog` fora do modo demonstração | 404 |
| Cabeçalho `X-Frame-Options: SAMEORIGIN` | presente |
| `/admin` e `/admin/receitas` sem login | redirecionam para `/entrar` |
| `/api/chef` e `/api/checkout` sem login | 401 |
| `/api/health` sem administrador | 403 |
| Webhook sem assinatura, com assinatura errada ou com id adulterado | 401 |
| Webhook com assinatura válida | aceito; segue para a consulta do pagamento |
| Texto de receitas ou nomes de chaves privadas nos arquivos enviados ao navegador | nenhum |

## O que NÃO foi possível testar (depende de credenciais reais)

| Item | Situação |
| --- | --- |
| Projeto Supabase hospedado — login por senha, RLS pela API, funções, Storage e app no navegador | ✅ **testado em 11/11/2026** (seção “Testes contra o Supabase real”) |
| Cadastro com e-mail de confirmação e recuperação de senha | **Não executados**: dependem de uma caixa de e-mail real e do endereço público do app. O gatilho que cria o perfil foi exercitado; o envio e o clique no link, não |
| OpenAI | Chamada implementada, **não executada** (sem chave). O respondedor por consulta direta às fichas foi testado |
| Mercado Pago | Assinatura do webhook e regras de liberação testadas; criação de preferência e pagamento real **não executados** |
| Deploy na Vercel | Build de produção validado localmente; deploy **não executado** |

Roteiro para concluir esses testes: seção 8 de [CONFIGURACAO.md](CONFIGURACAO.md).

## Testes contra o Supabase real (11/11/2026)

Feitos no projeto `clube_da_ceia_perfeita` (PostgreSQL 17.11), com dois usuários temporários que foram
apagados ao final. O banco terminou idêntico à carga do repositório, sem nenhum registro de teste.

| O quê | Como repetir | Resultado |
| --- | --- | --- |
| Instalação: 5 migrations + carga | histórico em `supabase_migrations.schema_migrations` | o texto registrado de cada migration tem o mesmo MD5 do arquivo local |
| Banco hospedado × repositório (dados, estrutura e permissões das roles da API) | `npm run db:conferir` → colar `supabase/.temp/conferencia.sql` no SQL Editor | 28 de 28 verificações iguais |
| API pública: visitante, cliente sem acesso, cliente com cortesia e administrador | `npm run test:hosted` (`tests/hosted/smoke.mjs`) | 56 de 56 |
| App no navegador em modo Supabase (login, cookies, `/admin`, telas, Chef, gravações) | `python3 tests/e2e/fluxo_supabase.py` | 26 de 26, sem erros de console |

O teste da API cobre, entre outros: login por e-mail e senha; perfil criado pelo gatilho; cliente não vira
admin nem lê dados alheios; conteúdo premium só com acesso válido **e** ficha publicada; publicação bloqueada
sem aprovação; auditoria com autoria; desafios calculados no servidor; PDFs originais inacessíveis a clientes;
fotos de desafio só na própria pasta; revogação do acesso com efeito imediato.

**Defeitos que só apareceram no ambiente real (corrigidos):**

1. `POST /api/chef` respondia 500: a pergunta e a resposta eram gravadas em lote com colunas diferentes e o
   PostgREST preenchia as ausentes com `NULL`. Corrigido com `defaultToNull: false` na rota e no
   `SupabaseStore.insert` (vale para todas as inserções em lote do app).
2. Administradores enviavam capas para `recipe-images`, mas não conseguiam substituí-las nem removê-las (faltava
   a policy de leitura). Corrigido na migration `20261111180506_storage_capas_select.sql`.
3. Mensagem do link de e-mail aberto em outro navegador dizia “link inválido”; agora orienta a entrar com a senha.

### Como rodar os testes contra o projeto real

Use **somente contas de teste**. Crie dois usuários com a mesma senha (um deles com `profiles.role = 'admin'`) e:

```bash
SUPABASE_URL=https://xxxx.supabase.co SUPABASE_PUBLISHABLE_KEY=sb_publishable_... \
TEST_ADMIN_EMAIL=admin-teste@... TEST_CUSTOMER_EMAIL=cliente-teste@... TEST_PASSWORD=... \
npm run test:hosted
```

O teste só cria registros marcados com `zz-teste`, começa removendo as sobras da execução anterior e apaga
pela API o que as contas de teste conseguem apagar. **Limpeza** do que sobra (SQL Editor):

```sql
delete from public.memberships where season_id in (select id from public.seasons where slug like 'zz-teste%');
delete from public.seasons where slug like 'zz-teste%';
delete from auth.users where email in ('admin-teste@...', 'cliente-teste@...'); -- apaga também os dados dessas contas
delete from public.admin_audit_logs where actor_email in ('admin-teste@...', 'cliente-teste@...');
```

Para o teste no navegador: `SMOKE_KEEP=1 npm run test:hosted` (mantém a ficha e o acesso de teste), suba o app
com as chaves do Supabase e rode `tests/e2e/fluxo_supabase.py` com as mesmas variáveis e `BASE_URL`.
