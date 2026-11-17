# Manual do administrador — Clube da Ceia Perfeita

**Versão:** 1.0  
**Aplicativo:** https://clubedaceia.vercel.app  
**Repositório:** https://github.com/facunip2018-png/clube_da_ceia  
**Supabase:** projeto nnfpsayxjwyqnixmmzhl

Este é o guia operacional para manter o Clube funcionando. Ele separa o que já foi construído do que precisa de configuração, validação ou desenvolvimento.

> **Regra de arquitetura:** Supabase é o banco de dados, autenticação, permissões e armazenamento. Vercel é somente hospedagem e implantação do aplicativo. Dados e conteúdo persistente não devem ser transferidos para a Vercel.

## 1. Estrutura do projeto

| Serviço | Responsabilidade | Situação conhecida |
| --- | --- | --- |
| Supabase | PostgreSQL, login, RLS, arquivos privados e dados do aplicativo | Projeto ativo; banco e segurança instalados e testados anteriormente |
| GitHub | Código-fonte e histórico de alterações | Repositório existente e conectado |
| Vercel | Hospedagem e implantação do Next.js | Aplicativo publicado; commits na branch principal podem iniciar deploy |
| Mercado Pago | Checkout e confirmação de pagamentos | Checkout Pro e webhook implementados; operação real precisa de validação |
| OpenRouter/Kimi | IA utilizada no fluxo administrativo de leitura/importação de documentos | Chave cadastrada no cofre do Supabase |
| Chef | Respostas sobre receitas publicadas | Rota de servidor implementada; IA generativa depende do provedor configurado |
| Gumlet | Hospedagem e reprodução de vídeos | Biblioteca administrativa, player HLS/MP4 e publicação implementados; falta testar os ativos reais e revisar privacidade no Gumlet |

## 2. O que já foi construído

### Aplicativo
- Next.js com interface responsiva para computador e celular.
- Navegação do cliente: Início, Coleções, Minha ceia, Lista de compras, Chef e Perfil.
- Painel administrativo protegido por autenticação e papel de administrador.
- Catálogo organizado por coleções, sem venda individual de receitas.
- Fichas estruturadas em componentes, ingredientes e etapas.
- Páginas de detalhe de receita e modo cozinheiro.

### Banco de dados e segurança
O Supabase contém estrutura para perfis, temporadas, coleções, documentos de origem, receitas, componentes, ingredientes, etapas, favoritos, planos de ceia, listas de compras, sessões de preparo, conversas com o Chef, pedidos, transações, acessos e auditoria.

Controles implementados e testados anteriormente:
- RLS nas tabelas para separar dados de cada pessoa.
- Papéis de cliente e administrador controlados no banco.
- Proteção do painel administrativo no servidor.
- Conteúdo completo restrito a pessoas com acesso válido e receitas publicadas.
- PDFs originais em bucket privado.
- Chaves privadas somente no servidor.
- Registro de ações administrativas em auditoria.

**Não desative RLS, não torne o bucket de PDFs público e não coloque chaves secretas no código do navegador.**

### Conteúdo
Foram trabalhadas coleções de panetones e chocotones, tortas doces, pudins, pavês, rabanadas recheadas e manjares.

**Manjares:** nove receitas foram cadastradas no Supabase e estruturadas em componentes. No último levantamento registrado havia 26 componentes, 89 ingredientes e 64 etapas, todos associados ao documento de origem.

As documentações técnicas antigas ainda contêm tabelas de conteúdo desatualizadas. Para saber o catálogo atual, consulte o painel e o Supabase; não use contagens antigas como retrato atual.

### Ferramentas do cliente
- Calculadora de porções baseada no rendimento informado.
- Planejador da ceia e cronograma.
- Lista de compras com agrupamento de ingredientes compatíveis.
- Favoritas por usuário.
- Modo cozinheiro com etapas sequenciais, retomada e temporizadores.
- Chef com contexto de receitas publicadas.
- Desafios e progresso, quando habilitados.

A existência de uma função no código não substitui o teste na conta real do assinante e em produção.

## 3. Entrar no painel administrativo

1. Abra https://clubedaceia.vercel.app.
2. Entre com uma conta que tenha papel de administrador.
3. Abra **Painel admin**.
4. Use os módulos disponíveis para gerenciar documentos, receitas, coleções, temporada, pessoas e pagamentos.

Se o item não aparecer, verifique no Supabase se o perfil possui o papel correto. Não tente resolver alterando permissões do navegador.

## 4. Criar coleções e cadastrar receitas

### 4.1 Criar ou conferir uma coleção
1. Abra o painel.
2. Entre em **Coleções**.
3. Confira se a categoria já existe.
4. Se não existir, crie com nome, slug, descrição e imagem/capa, conforme os campos disponíveis.
5. Confira se aparece corretamente na navegação do cliente.

Use nomes claros e slugs estáveis. Evite duplicar categorias do mesmo assunto.

### 4.2 Cadastrar documento de origem
1. Entre em **Documentos**.
2. Cadastre o título do PDF e associe à coleção correta.
3. Informe autor/editora ou origem quando conhecido.
4. Registre quantidade de páginas e observações.
5. Envie o arquivo pelo painel para o Storage privado do Supabase.
6. Registre a situação da permissão comercial e a origem da autorização.

**O arquivo estar no cofre não significa que existe autorização para reproduzir ou comercializar seu conteúdo.** Não publique material protegido sem autorização comercial confirmada.

### 4.3 Ler e estruturar o PDF
O projeto possui fluxo administrativo de extração/importação de conteúdo. Quando disponível para o documento:
1. Abra o documento cadastrado.
2. Acione **Ler PDF e cadastrar receitas**.
3. Aguarde extração e processamento.
4. Confira páginas lidas e receitas identificadas.
5. Verifique se o PDF é digital ou escaneado. Páginas formadas apenas por imagens podem precisar de OCR.
6. Confira as fichas geradas e os pontos de revisão.

O processamento por IA é assistido. Não aceite automaticamente números, ingredientes, temperaturas ou etapas que não estejam no original. Se a leitura falhar, não publique conteúdo parcial. Tente novamente ou use transcrição fiel das páginas legíveis.

### 4.4 Organizar por componentes
Uma receita pode ter partes como massa, base, creme, recheio, calda, cobertura, montagem, fritura e finalização.

Para cada ficha:
- Cadastre as partes na ordem correta de preparo.
- Associe ingredientes e etapas ao componente correto.
- Use componentes compartilhados apenas quando a relação e o multiplicador estiverem corretos.
- Confira nomes, quantidades, unidades e texto original.
- Confira ordem das etapas.
- Confira páginas de origem.
- Cadastre tempos e temporizadores somente quando informados.
- Confira dicas, observações, utensílios e rendimento.

### 4.5 Revisar, aprovar e publicar
O fluxo editorial possui estados de rascunho, revisão, aprovada, publicada, aguardando permissão e arquivada.

Antes de publicar:
1. Confira a ficha completa.
2. Resolva os pontos de revisão.
3. Confira se ingredientes e etapas estão associados a uma parte.
4. Verifique origem e páginas.
5. Confirme a permissão comercial no registro do documento.
6. Aprove a ficha.
7. Publique somente quando todos os requisitos forem atendidos.
8. Abra a receita no aplicativo com uma conta de cliente e confira a apresentação.

Não publique para esconder falha de importação. Se faltar informação, mantenha a ficha em revisão ou rascunho.

## 5. Temporada, preço e acesso

O acesso pago é organizado por temporadas. O painel permite configurar dados como preço, datas e situação.

Checklist antes de abrir vendas:
- [ ] Nome e descrição da temporada.
- [ ] Preço correto em reais.
- [ ] Início e encerramento das vendas.
- [ ] Período de validade do acesso.
- [ ] Estado da temporada configurado.
- [ ] Receitas que serão oferecidas publicadas.
- [ ] Compra de teste aprovada e acesso conferido.
- [ ] Reembolso/estorno de teste e revogação conferidos.

Não abra vendas apenas porque a tela está pronta. Faça primeiro o teste completo de pagamento e liberação.

## 6. Mercado Pago — Checkout Pro e webhook

### 6.1 O que já existe
O código prevê:
1. Criação de pedido usando preço cadastrado no banco.
2. Criação da preferência do Checkout Pro.
3. Retorno informativo ao comprador.
4. Recebimento do evento pelo webhook.
5. Validação da assinatura do webhook.
6. Consulta do pagamento diretamente à API do Mercado Pago.
7. Conferência de valor e moeda.
8. Processamento idempotente para evitar liberação duplicada.
9. Tratamento de aprovado, pendente, recusado, cancelado, reembolso, estorno e disputa.
10. Liberação ou revogação do acesso conforme resultado validado.

A página de retorno do checkout não prova que houve pagamento. A liberação deve ocorrer pelo evento validado no servidor.

### 6.2 Configurar webhook
1. Entre em https://www.mercadopago.com.br/developers.
2. Abra a aplicação utilizada pelo Clube.
3. Acesse **Suas integrações → Webhooks** (o nome pode variar).
4. Cadastre a URL:

   https://clubedaceia.vercel.app/api/webhooks/mercadopago

5. Selecione o evento **Pagamentos**.
6. Salve.
7. Copie a **assinatura secreta** do webhook.
8. Cadastre-a como variável de ambiente de produção na Vercel.
9. Cadastre também o Access Token correspondente.
10. Confirme que a chave de serviço do Supabase está disponível somente no servidor.
11. Mantenha pagamentos desligados até concluir os testes.
12. Configure credenciais de teste e faça uma compra de teste.
13. Confira em **Painel admin → Pessoas e pagamentos** se o pedido foi aprovado e o acesso liberado.
14. Teste pagamento pendente, recusado e reembolso/estorno.
15. Só depois de validar o ciclo completo, troque para credenciais de produção.

### 6.3 Variáveis de ambiente
| Variável | Finalidade | Regra |
| --- | --- | --- |
| PAYMENTS_ENABLED | Liga/desliga checkout | Manter false até concluir testes |
| MERCADOPAGO_ACCESS_TOKEN | Acesso à API de pagamentos | Segredo de servidor |
| MERCADOPAGO_WEBHOOK_SECRET | Validar assinatura do webhook | Segredo de servidor |
| SUPABASE_SERVICE_ROLE_KEY | Operações administrativas do servidor | Nunca expor no navegador |
| NEXT_PUBLIC_SITE_URL | URL pública usada em retornos | Deve corresponder ao domínio oficial |

**Situação:** fluxo e validações do webhook estão implementados e as regras de assinatura/pagamento foram cobertas por testes automatizados. Criação de preferência e pagamento real não estavam comprovados no último relatório consultado. Considere a integração implementada, mas dependente de validação operacional com credenciais reais.

## 7. Gumlet — vídeos e player

### 7.1 Situação atual
A biblioteca de vídeos foi implementada no painel em **Painel admin → Vídeos Gumlet**. Há um botão grande e destacado na visão geral do painel para abrir essa área. O cadastro fica no Supabase e o player aparece na área **Vídeos** do assinante.

O primeiro registro foi criado como **rascunho**, com o link HLS que você forneceu. Ele não fica visível aos assinantes até ser publicado.

O link fornecido é uma URL HLS (.m3u8):

https://video.gumlet.io/6ad7bb851ab4445ed4e7f416/6ad7c30a1ab4445ed4e82f97/main.m3u8

Esse endereço é um manifesto de streaming. Ele não cria automaticamente uma biblioteca no painel, uma página de vídeo ou um player com controles.

### 7.2 Como deverá funcionar
Criar uma seção **Vídeos** no painel administrativo e uma área de exibição para o assinante.

Campos recomendados:
- Título e descrição.
- Coleção/categoria relacionada.
- Receita relacionada, se houver.
- URL HLS do Gumlet (.m3u8).
- URL MP4 alternativa, se habilitada no Gumlet.
- Imagem de capa/thumbnail.
- Duração, quando conhecida.
- Ordem de exibição.
- Situação: rascunho ou publicado.
- Visibilidade: todos os assinantes autorizados ou somente uma coleção/receita.

Fluxo administrativo implementado:
1. Abrir **Painel admin → Vídeos**.
2. Cadastrar título e descrição.
3. Colar a URL HLS.
4. Opcionalmente cadastrar URL MP4 e imagem de capa.
5. Associar o vídeo a uma coleção ou receita.
6. Escolher rascunho, publicado ou arquivado.
7. Conferir a prévia do player ao lado do formulário.
8. Salvar. Ao publicar, o vídeo fica visível somente a assinantes com acesso ativo.

Fluxo do cliente:
1. Entrar com conta com acesso válido.
2. Abrir a coleção, receita ou área de vídeos.
3. Selecionar o vídeo.
4. Reproduzir, pausar, ajustar volume e usar tela cheia.

### 7.3 HLS ou MP4?
**HLS (.m3u8):** é o formato do link fornecido e é apropriado para streaming adaptativo. Porém, a compatibilidade varia por navegador. O player deve tratar a reprodução HLS; não basta presumir que qualquer navegador reproduzirá o manifesto diretamente em um elemento de vídeo.

**MP4:** pode ser habilitado nas configurações de processamento do Gumlet para gerar acesso MP4 aos novos vídeos, conforme a opção do painel Gumlet. Isso é uma configuração de processamento/entrega do Gumlet; não cria o cadastro administrativo nem o player dentro do Clube.

**Recomendação:** usar HLS como formato principal e, se o Gumlet disponibilizar MP4 para os vídeos, guardar também essa URL como alternativa. O player deve escolher a fonte compatível e mostrar mensagem clara se não conseguir reproduzir.

### 7.4 Segurança
- Não colocar tokens privados do Gumlet no navegador.
- Não salvar credenciais administrativas em campos públicos.
- Se vídeos forem exclusivos de assinantes, proteger a página e validar o acesso no servidor.
- Confirmar no Gumlet se o asset está configurado para acesso público ou protegido.
- Não considerar um vídeo privado apenas porque o link não foi divulgado.

Pendências Gumlet:
- [ ] Confirmar no painel Gumlet se os ativos e URLs HLS/MP4 estão liberados para reprodução no domínio do Clube.
- [ ] Conferir a privacidade dos ativos e configurar proteção/tokenização no Gumlet se necessário.
- [ ] Habilitar MP4 nas configurações de processamento do Gumlet para os vídeos em que desejar essa alternativa.
- [ ] Testar reprodução real em Android, iPhone, Chrome e Safari.
- [ ] Testar bloqueio de usuário sem acesso e confirmar que o link direto não contorna a proteção do Gumlet.

## 8. Chef e leitura de documentos

### Chef
- O endpoint do Chef funciona no servidor e recebe contexto de receitas publicadas.
- A chave do provedor deve permanecer secreta.
- Sem IA generativa configurada, o aplicativo pode responder por consulta direta à ficha, identificando esse modo.
- Monitore limites de uso e erros do provedor.

### Leitura/importação de PDF
- Os documentos ficam no Storage privado do Supabase.
- A extração de texto é feita por páginas.
- PDFs escaneados podem precisar de OCR.
- O texto extraído pode ser enviado ao serviço de IA para estruturar rascunhos.
- Em caso de resposta inválida do provedor, o fluxo deve sinalizar falha, não publicar conteúdo incompleto.
- Confira sempre o resultado com o documento original.

A chave OpenRouter/Kimi foi cadastrada no cofre do Supabase para o fluxo administrativo. Não copie essa chave para arquivos do repositório ou variáveis públicas.

## 9. Supabase e Vercel

### Supabase
Usar para banco PostgreSQL, login, sessões, RLS, Storage privado, funções e rotinas do banco.

Cuidados:
- Não executar instalação completa sobre o banco de produção.
- Aplicar migrations novas de forma controlada.
- Conferir histórico de migrations.
- Fazer backup antes de alterações estruturais importantes.
- Não remover políticas RLS para corrigir erro de tela.
- Não tornar o bucket source-documents público.

### Vercel
Usar somente para hospedar o Next.js, construir e publicar versões do código, configurar variáveis do servidor e consultar logs.

Não criar banco de dados nem armazenar conteúdo de receitas como persistência na Vercel.

Revisar no ambiente de produção:
- NEXT_PUBLIC_SUPABASE_URL
- NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
- SUPABASE_SERVICE_ROLE_KEY (somente servidor)
- NEXT_PUBLIC_SITE_URL
- PAYMENTS_ENABLED
- MERCADOPAGO_ACCESS_TOKEN
- MERCADOPAGO_WEBHOOK_SECRET
- Chave do provedor do Chef, conforme integração ativa

Depois de alterar variável, faça nova implantação para que o aplicativo use o valor atualizado.

## 10. E-mail e autenticação

Antes de abrir vendas ao público:
- [ ] Conferir Site URL do Supabase com o domínio de produção.
- [ ] Conferir Redirect URLs.
- [ ] Conferir modelos de confirmação e recuperação de senha.
- [ ] Configurar SMTP próprio para envio confiável em escala.
- [ ] Testar cadastro com e-mail real.
- [ ] Testar confirmação em outro navegador/dispositivo.
- [ ] Testar recuperação e redefinição de senha.

Não prometa envio instantâneo sem validar o provedor e seus limites.

## 11. Rotina operacional

### Antes de abrir uma temporada
- [ ] Conferir preço, datas e período de acesso.
- [ ] Conferir receitas publicadas e permissões comerciais.
- [ ] Conferir login e recuperação de senha.
- [ ] Fazer compra de teste.
- [ ] Confirmar webhook e liberação de acesso.
- [ ] Testar bloqueio e revogação após reembolso.
- [ ] Conferir site em celular e computador.
- [ ] Conferir canal de suporte.

### Ao adicionar receitas
- [ ] Criar/conferir coleção.
- [ ] Cadastrar documento de origem.
- [ ] Registrar permissão comercial.
- [ ] Ler/transcrever conteúdo.
- [ ] Conferir ingredientes, quantidades, etapas e páginas.
- [ ] Organizar componentes.
- [ ] Resolver pontos de revisão.
- [ ] Aprovar e publicar.
- [ ] Testar ficha, calculadora, lista e modo cozinheiro como cliente.

### Semanalmente
- [ ] Conferir pedidos pendentes e falhas de webhook.
- [ ] Conferir erros do app e do provedor de IA.
- [ ] Conferir documentos e receitas em revisão.
- [ ] Conferir vídeos e links ativos.
- [ ] Conferir acessos suspensos, reembolsos e disputas.
- [ ] Verificar backups e estado do Supabase.

## 12. Matriz de situação

| Área | Situação | Próxima ação |
| --- | --- | --- |
| Aplicativo e navegação | Implementado | Revisar em celular e computador |
| Supabase: banco, Auth, RLS e Storage | Instalado e testado anteriormente | Manter migrations e conferir alterações |
| GitHub | Repositório criado e conectado | Manter commits e histórico |
| Vercel | Aplicativo publicado | Monitorar deploys; usar somente como hospedagem |
| Coleções e fichas | Conteúdo cadastrado, incluindo nove manjares estruturados | Continuar revisão e inclusão |
| Calculadora, ceia e lista | Implementados | Regressão com conta de assinante |
| Favoritas e modo cozinheiro | Implementados | Testar fluxo em produção |
| Chef | Implementado; modo generativo depende do provedor | Confirmar provedor, limites e custos |
| Importação PDF/OCR | Fluxo implementado | Validar cada documento e corrigir falhas |
| Mercado Pago Checkout Pro | Fluxo implementado | Configurar/confirmar credenciais e testar compra |
| Webhook Mercado Pago | Rota e validações implementadas | Confirmar URL, evento, segredo e entrega real |
| Temporada e preço | Campos e fluxo administrativo existentes | Definir preço e datas |
| E-mail transacional | Autenticação implementada | Configurar SMTP e testar ponta a ponta |
| Download do PDF original pelo assinante | Não confirmado; documentação atual registra acesso administrativo aos originais | Decidir política e implementar acesso seguro se desejado |
| Biblioteca de vídeos Gumlet | Implementada no painel e no espaço do assinante | Testar os ativos reais e revisar privacidade no Gumlet |
| Player HLS/MP4 Gumlet | Implementado com HLS.js e alternativa MP4 | Testar nos aparelhos e navegadores reais |
| Compra real de ponta a ponta | Não comprovada no último relatório consultado | Testar com credenciais de teste |
| Manual do cliente | Criado neste conjunto de documentação | Atualizar quando os fluxos mudarem |
| Manual do administrador | Este documento | Atualizar quando integrações mudarem |

## 13. Regras de segurança obrigatórias

1. Nunca colocar chave service_role, Access Token do Mercado Pago, segredo do webhook ou chave de IA no navegador.
2. Nunca conceder acesso pago com base apenas na página de retorno do checkout.
3. Nunca aceitar webhook sem validar assinatura e consultar o pagamento na API.
4. Nunca liberar conteúdo premium para conta sem acesso válido.
5. Nunca tornar PDFs originais públicos.
6. Nunca desativar RLS para corrigir falha de interface.
7. Nunca publicar receita sem revisão e autorização comercial confirmada.
8. Nunca inventar ingredientes, quantidades, tempos ou etapas.
9. Nunca usar Vercel como banco de dados.
10. Nunca apagar dados ou migrations de produção sem backup, análise de dependências e plano de reversão.

## 14. Plano de conclusão recomendado

1. Confirmar cadastro, confirmação de e-mail e recuperação de senha.
2. Definir temporada, preço e período de acesso.
3. Configurar e testar Mercado Pago, incluindo webhook, aprovação e estorno.
4. Revisar permissões comerciais e fichas que serão oferecidas.
5. Decidir a política de download dos PDFs originais para assinantes.
6. Configurar privacidade e, se necessário, MP4 no painel Gumlet.
7. Testar o player com o vídeo cadastrado em computador e celular.
8. Fazer testes ponta a ponta com conta de cliente.
9. Abrir as vendas somente depois da conferência.

**Princípio final:** toda mudança deve preservar usuários, assinaturas, receitas, permissões e dados existentes. Antes de alterar banco, autenticação ou pagamento, inspecione o estado atual, faça backup quando aplicável, implemente a menor mudança necessária e teste o resultado.
