# Configuração — do zero ao ar

Tempo estimado: 30 a 40 minutos. Faça na ordem.

> **Situação em 11/11/2026 — o que já está pronto neste projeto**
>
> | Etapa | Situação |
> | --- | --- |
> | 1. Supabase — banco, regras de segurança, buckets e catálogo | ✅ instalado e conferido no projeto `clube_da_ceia_perfeita` (ref `nnfpsayxjwyqnixmmzhl`) |
> | 1. Supabase — Site URL, Redirect URLs e modelos de e-mail | ⏳ depende do endereço da Vercel (passos 3 e 4 abaixo) |
> | 2. GitHub — `github.com/facunip2018-png/clube_da_ceia` | ⏳ repositório criado e vazio; falta o `git push` (e torná-lo **privado**) |
> | 3. Vercel | ⏳ a fazer |
> | 4. Primeiro administrador | ⏳ depois do primeiro cadastro |
>
> Valores **públicos** deste projeto (podem ir para a Vercel como estão):
>
> ```
> NEXT_PUBLIC_SUPABASE_URL=https://nnfpsayxjwyqnixmmzhl.supabase.co
> NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_KP7gAP0h9s4DrV2LVYVy7Q_GMPZ1urp
> ```
>
> A chave **secreta** (`SUPABASE_SERVICE_ROLE_KEY`) não está em nenhum arquivo: copie em
> Supabase → Project Settings → API Keys e cole somente na Vercel.

## 1. Supabase (banco de dados, login e arquivos)

1. Crie um projeto em <https://supabase.com> (região sugerida: **South America (São Paulo)**).
   *(feito: o projeto atual está em `us-east-1`; a região não pode ser trocada depois, só criando outro projeto.)*
2. Abra **SQL Editor → New query**, cole **todo** o conteúdo de `supabase/setup_completo.sql` e clique em **Run**.
   Esse arquivo cria as 31 tabelas, as funções, as regras de segurança (RLS), os 3 buckets de arquivos e
   carrega o catálogo. Pode ser executado uma única vez em um projeto novo.
   *(feito no projeto atual: as 5 migrations de `supabase/migrations/` estão registradas no histórico do
   Supabase com os mesmos números de versão dos arquivos, e a carga `supabase/seed.sql` foi aplicada.
   **Não execute o `setup_completo.sql` de novo nesse projeto.**)*
   - Alternativa com a CLI: `supabase link --project-ref SEU_REF` → `supabase db push` → depois execute `supabase/seed.sql` no SQL Editor.
   - Para conferir a qualquer momento se o banco bate com o repositório: `npm run db:conferir` e cole o
     arquivo gerado (`supabase/.temp/conferencia.sql`) no SQL Editor — todas as linhas devem vir com `ok = true`.
3. Em **Authentication → URL Configuration**:
   - **Site URL**: o endereço público do app (ex.: `https://clube.seudominio.com.br`). Hoje está `http://localhost:3000`.
   - **Redirect URLs**: adicione `https://SEU-DOMINIO/auth/callback` e, para testar no computador, `http://localhost:3000/auth/callback`.
4. Em **Authentication → Emails → Templates**, troque o link de dois modelos. Com o link padrão, a confirmação só
   funciona se a pessoa abrir o e-mail **no mesmo navegador** em que se cadastrou; com estes, funciona em qualquer aparelho:
   - **Confirm signup**: `<a href="{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=email&next=/">Confirmar meu e-mail</a>`
   - **Reset password**: `<a href="{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=recovery">Criar nova senha</a>`
   - O envio de e-mails embutido do Supabase é limitado (hoje, 2 e-mails por hora). Antes de abrir as vendas,
     configure um SMTP próprio em **Authentication → Emails → SMTP Settings**.
5. Em **Project Settings → API**, copie:
   - `Project URL` → `NEXT_PUBLIC_SUPABASE_URL`
   - chave pública (`publishable` ou `anon`) → `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
   - chave secreta (`service_role` ou `secret`) → `SUPABASE_SERVICE_ROLE_KEY` (**nunca** no navegador)

> Quando chegarem novas fichas, basta executar de novo o `supabase/seed.sql` atualizado: ele só acrescenta o
> que é novo e **não sobrescreve** nada do que foi ajustado no painel.

## 2. GitHub

O repositório precisa ser **Private** (privado): os arquivos de conteúdo trazem o texto das receitas dos
e-books — é o conteúdo pago do app e, no caso do Pavê, de um PDF sem termo de licença. O repositório
`facunip2018-png/clube_da_ceia` foi criado como **público**: antes de enviar o código, mude em
**Settings → General → Danger Zone → Change repository visibility → Make private**.

Com o Git instalado, dentro da pasta do projeto (a que veio no `.zip`):

```bash
git init -b main
git add .
git commit -m "Clube da Ceia Perfeita — base do app"
git remote add origin https://github.com/facunip2018-png/clube_da_ceia.git
git push -u origin main
```

Na primeira vez o Git abre o navegador para você entrar no GitHub. Sem terminal: instale o **GitHub Desktop**,
use *File → Clone repository* para baixar o `clube_da_ceia` (vazio), copie para essa pasta todo o conteúdo do
`.zip` (inclusive os arquivos que começam com ponto, como `.gitignore`), escreva um resumo e clique em
*Commit to main* → *Push origin*.

O `.gitignore` já impede o envio de chaves (`.env*`) e de PDFs (`*.pdf`). **Não versione os e-books.**

## 3. Vercel

1. <https://vercel.com> → **Add New → Project** → importe o repositório. O framework (Next.js) é detectado sozinho.
2. Em **Settings → Environment Variables**, cadastre (Production e Preview):

| Variável | Obrigatória | Observação |
| --- | --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | sim | |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | sim | chave pública |
| `SUPABASE_SERVICE_ROLE_KEY` | para pagamentos | somente servidor |
| `NEXT_PUBLIC_SITE_URL` | recomendada | endereço público, sem barra no final |
| `OPENAI_API_KEY` | opcional | sem ela o Chef responde por consulta direta às fichas |
| `OPENAI_MODEL` | opcional | padrão `gpt-6-luna` |
| `CHEF_DAILY_LIMIT` | opcional | padrão 30 perguntas por pessoa a cada 24 h |
| `PAYMENTS_ENABLED` | — | deixe `false` até terminar os testes |
| `MERCADOPAGO_ACCESS_TOKEN` | para pagamentos | |
| `MERCADOPAGO_WEBHOOK_SECRET` | para pagamentos | “assinatura secreta” do painel de Webhooks |

3. **Settings → General → Node.js Version**: 22.x ou mais nova (o `supabase-js` já avisa que o Node 20 deixará de ser suportado).
   No plano Hobby, a Vercel pode bloquear o deploy de um repositório privado quando o autor do commit não é a
   conta dona do projeto: faça o commit com o seu próprio usuário do GitHub.
4. Faça o deploy. **Não** defina `NEXT_PUBLIC_DEMO_MODE` nem `ALLOW_IFRAME_EMBED` em produção.

## 4. Primeiro administrador

1. Abra o app publicado e crie sua conta em **Criar conta** (confirme o e-mail).
2. No Supabase, **SQL Editor**:

```sql
update public.profiles set role = 'admin' where email = 'seu-email@exemplo.com';
```

3. Saia e entre de novo: o item **Painel admin** aparece no menu. Outros administradores podem ser
   promovidos pelo próprio painel (Pessoas e pagamentos), com registro em auditoria.

## 5. Abrir a temporada (pelo painel)

O painel mostra um **Guia de publicação** com a situação de cada passo:

1. **Documentos** — envie cada PDF ao cofre privado e, quando houver autorização de uso, marque a
   permissão como *Confirmada*, registrando como ela foi obtida.
2. **Receitas** — abra cada ficha, resolva os pontos de revisão, *Aprove* e *Publique*.
3. **Temporada** — defina o preço, confira as datas e mude a situação para *Ativa*.

## 6. Mercado Pago (Checkout Pro)

1. Em <https://www.mercadopago.com.br/developers> crie uma aplicação do tipo **Checkout Pro**.
2. Comece com as **credenciais de teste**: copie o *Access Token* para `MERCADOPAGO_ACCESS_TOKEN`.
3. Em **Suas integrações → Webhooks → Configurar notificações**:
   - URL: `https://SEU-DOMINIO/api/webhooks/mercadopago`
   - Evento: **Pagamentos**
   - Copie a **assinatura secreta** para `MERCADOPAGO_WEBHOOK_SECRET`.
4. Defina `PAYMENTS_ENABLED=true`, faça novo deploy e teste a compra com um usuário de teste do Mercado Pago.
   Confira em **Painel admin → Pessoas e pagamentos** se o pedido ficou *approved* e o acesso foi liberado.
5. Só então troque para as credenciais de produção.

Como funciona: o app cria o pedido com o preço lido do banco → cria a preferência → a pessoa paga no
Mercado Pago → o webhook (assinado) chega ao servidor → o servidor consulta o pagamento na API do Mercado
Pago, confere valor e moeda e libera o acesso. A página de retorno apenas informa a situação.

## 7. OpenAI (Chef IA)

Crie uma chave em <https://platform.openai.com/api-keys> e cadastre `OPENAI_API_KEY` na Vercel. A chave
é usada apenas na rota de servidor `/api/chef`. O Chef recebe somente as fichas **publicadas** que a
pessoa pode ler e tem instruções para não inventar dados e para avisar quando uma substituição não faz parte da receita original.

## 8. Conferência final

- [ ] `/admin` sem login redireciona para `/entrar`
- [ ] Uma conta comum não vê “Painel admin” nem consegue abrir `/admin`
- [ ] Visitante vê a capa das receitas publicadas, mas não ingredientes nem etapas
- [ ] Compra de teste aprovada libera o acesso; reembolso de teste retira
- [ ] O app pode ser instalado no celular (menu do navegador → Instalar / Adicionar à Tela de Início)
