# Equipe com cara de WhatsApp + marcação com @

Data: 02/11/2026. Aprovado em conversa com o Eduardo; o visual é o mockup abaixo.
Base: ADR 0011 (chat da equipe como caixa do Chatwoot, PR #305). Este desenho **não
reabre** a decisão de manter o chat dentro de Conversas.

## Por quê

O chat interno virou caixa do Chatwoot e herdou a cara de atendimento: toda mensagem
aparece à direita em verde, inclusive a dos colegas, porque o sistema trata toda
mensagem de usuário como "enviada pelo escritório". O topo e a caixa de escrever
trazem controles de atendimento (resolver, nota privada), e não há como chamar uma
pessoa específica num grupo. A equipe conhece o WhatsApp e deve usar o chat sem
aprender nada.

**Prazo (decisão do Eduardo):** os 8 objetivos no ar até **16/11/2026**, quando entram
SDR e Closer. Se algo ficar em risco, avisar o Eduardo antes, para ele decidir o que
atrasa. Ordem de trabalho: bolhas, caixa de escrever, apagar e @; depois lista, responder
e digitando; depois vistos; reações por último.

## Alvo visual

`comercial\docs\mockups\2026-11-02-equipe-whatsapp\equipe.html` (prints `claro.png`,
`claro-marcando.png`, `escuro.png`), aprovado pelo Eduardo em 02/11. É o alvo fiel,
nos dois temas. Divergência só com motivo técnico, e avisada.

Cores: as que o hub já tem. Enviada = `--ramon-enviada`; colega = `n-slate-4`;
contador = `--ramon-nao-lida` translúcido; marcação, citação e destaque = azul do hub.
Fundo colorido sempre translúcido. Sem papel de parede.

## Objetivos

Tudo vale **só na caixa Equipe** (`inbox.equipe`).

### 1. Conversa

- **Lado:** minha mensagem à direita, em verde. Colega à esquerda, em cinza.
- **Grupo (Geral, Setor):** colega com nome e foto; mensagens seguidas do mesmo autor
  agrupadas, com nome e foto só na primeira.
- **1:1:** sem nome nem foto na bolha, como no WhatsApp.
- **Admin em conversa de que não participa = só leitura (decisão do Eduardo):** os dois
  lados à esquerda, com nome e foto, e no lugar da caixa de escrever "Você está lendo como
  administrador". Não escreve, não reage, não apaga e não aparece digitando. O servidor
  recusa essas ações, e a tela não as oferece. Muda o que o admin pode hoje: ele continua
  vendo tudo, mas não escreve em conversa alheia.
- **Separador de dia** ("Hoje", "Ontem", data) e hora dentro da bolha.
- **Topo:** foto, nome e "N participantes" no grupo; embaixo, "Fulano está digitando…".
  Saem resolver, adiar, atribuir, mais ações, chamada, painel do lead e IA.
- **Caixa de escrever:** emoji, anexo, gravar áudio, campo e enviar. Saem as abas
  Responder/Nota privada, respostas prontas, assinatura e copiloto. O áudio continua,
  embora o mockup não mostre o microfone.
- **Enter envia, Shift+Enter quebra linha**, só na Equipe, sem mudar a preferência da
  pessoa nas conversas com clientes.
- **Menu da bolha:** copiar, responder, apagar. Saem "resposta pronta", "virar FAQ",
  "traduzir" e demais opções de atendimento.

### 2. Lista da esquerda

Foto, nome, hora da última mensagem, prévia e contador verde. A 1:1 mostra nome e foto da
outra pessoa ("Brenda", não "Brenda e Eduardo"), na lista, no topo e na notificação; quem
resolve é o navegador, a partir dos participantes, porque o contato sintético é único.
Admin de fora continua vendo "Brenda e Eduardo". A prévia traz "Fulano:"
nos grupos e "Você:" nas minhas, e mostra a marcação como `@Nome`, nunca o texto cru
`mention://`. Sem caixa, responsável, etiquetas, prioridade ou prazo. Selo azul `@`
quando há marcação minha ainda não lida. O seletor "Nova conversa 1:1…" e o aviso
"Administradores podem ler as conversas." continuam.

### 3. Marcação com @

- **Quem aparece:** só quem participa daquele chat (menos a própria pessoa), mais
  `@todos` nos grupos. Na 1:1, só a outra pessoa, sem `@todos`. Busca por nome ao digitar.
- **O @ nunca adiciona ninguém à conversa.**
- **Efeito:** todos continuam recebendo o aviso normal (som, sino, contador). Quem foi
  marcado recebe o aviso como "Fulano te marcou" em vez do aviso comum (uma notificação
  por pessoa, nunca duas), vê o próprio nome em destaque na bolha e o selo `@` na lista.
  `@todos` tem esse efeito para todos os participantes, menos quem escreveu.
- **Servidor valida:** id que não participa do chat é ignorado. Admin que não participa
  não pode ser marcado. Marcar a si mesmo não gera aviso.
- **O selo some** quando a pessoa lê a conversa (`last_seen_at`).
- **Aviso do sistema:** título "Fulano te marcou · Geral" e corpo com `@Nome`, nunca
  `mention://` (hoje `avisar` usa o conteúdo cru).
- **Sino:** o nativo guarda só a notificação mais recente por pessoa e conversa
  (`RemoveDuplicateNotificationJob`), então o "te marcou" pode sumir do sino com a mensagem
  seguinte. Aceito: o selo `@` na lista é o que permanece.
- **Conversas com clientes não mudam:** a marcação segue só na nota privada.

### 4. Responder citando

A opção "Responder" vale para minhas mensagens e as dos colegas. A citação aparece dentro
da bolha, com o nome do autor (o nativo não mostra), e clicar nela leva à mensagem original.
Reaproveita o `in_reply_to` nativo.

### 5. Digitando

Usa o evento nativo de digitação, que já chega aos participantes. Mostra o nome no topo.

### 6. Vistos

- **Só nas minhas mensagens.** ✓✓ cinza até ler, azul quando leram.
- **1:1:** azul quando a outra pessoa leu.
- **Grupo:** azul só quando todos leram. Passando o mouse: "Visto por 5 de 7. Falta:
  Tamires, Thaís." Conta todos os participantes, sem exceção para quem pouco abre o hub
  (decisão do Eduardo).
- **Ler é ver:** hoje a conversa marca como lida mesmo em aba de fundo
  (`onScrollToMessage` chama `makeMessagesRead` sem olhar visibilidade). Na Equipe, marca só
  com a aba visível e ao voltar para ela. Sem isso, o ✓✓ fica azul e o selo @ some sem
  ninguém ter visto.
- **Fonte:** `conversation_participants.last_seen_at`. Conta só quem participa, então
  admin lendo 1:1 alheia não vira visto. Quem escreveu não entra na conta.
- **Tempo real:** o ✓✓ muda sem recarregar quando alguém lê.
- **Quem entrou no time depois** começa com `last_seen_at` atual (regra existente) e
  conta como leitor só das mensagens anteriores a esse momento.

### 7. Reações

Seis emojis fixos (👍 ❤️ 😂 😮 😢 🙏), ao passar o mouse. Cada pessoa tem uma reação por
mensagem: outro emoji troca, o mesmo tira. O selo sob a bolha mostra emoji e quantidade,
com os nomes ao passar o mouse, e fica marcado se a reação é minha. Tempo real para quem
está na conversa. Só participantes reagem, para a reação não revelar que o admin está
lendo. Mensagem apagada não recebe reação. **Reação não gera aviso nem conta como
não-lida.** Atualização de mensagem que o navegador não tem carregada é ignorada na Equipe:
hoje o `ADD_MESSAGE` a trataria como nova, recuando a hora da conversa, rolando a tela e
marcando como lida.

### 8. Apagar só a própria mensagem

Hoje o endpoint de apagar não confere o autor, então qualquer participante apaga a
mensagem de um colega. Na Equipe: o autor, ou admin **que participa** daquela conversa,
conferido **no servidor** (e o menu só oferece a quem pode). Conversas com clientes não mudam.

## Não objetivos

- Sem tela própria, grupos criados por usuários, editar mensagem, fixar, encaminhar ou
  status online.
- Sem silenciar conversa nem mudar quem é avisado: toda mensagem segue tocando para todos.
- Sem push com navegador fechado (segue o limite do ADR 0011).
- Sem mudança nas conversas com clientes, nem na visão de admin.

## Anti-objetivos (se acontecer, falhou mesmo funcionando)

- Vazar 1:1: **ninguém vira membro da caixa Equipe** e a marcação não adiciona participante.
- O hub deixar de ser surdo: nada na Equipe pode criar lead, acionar IA, fluxo, automação,
  webhook ou BI. O guard do `AsyncDispatcher` continua sendo o único ponto.
- Regressão em conversa com cliente, especialmente:
  - Enter enviando mensagem a cliente;
  - bolha de cliente ou de agente mudando de lado ou de cor;
  - @ passando a funcionar em mensagem pública a cliente, o que mandaria `mention://` a ele.
- Reação ou leitura gerando som, notificação ou não-lida.
- Dado pessoal novo no ntfy (público). A marcação não usa o ntfy.

## Restrições

- Fork do Chatwoot v4.15.1: mudança em arquivo nativo com marca `FORK(ramon)`, e cada
  ponto novo registrado em `docs/FORK-PONTOS-DE-REGISTRO.md`.
- Sem ambiente Ruby local: quem valida é PR + CI; `rubocop-vps` antes do push.
- Kit visual do hub (`ramon/helpers/ui.js`, Tailwind, tokens); nada de creme ou off-white.
- **Sem migração**, por decisão de desenho (abaixo): não há regeneração de `schema.rb`.
- Atualizar o ADR 0011: o limite "Menção (@) não funciona na Equipe" deixa de valer.
- Aprovação de layout por **prints dos componentes reais** com dados de exemplo, claro e
  escuro (harness Vite + Chrome headless, o método de 03/10), **antes do merge**. Assim o
  deploy de outra frente na `ramon` não leva parte não aprovada. Depois do deploy, o smoke
  é a aprovação no uso (lição de 03/10: mockup aprovado não é aprovado no uso). Smoke = reescrever a seção O do
  consolidado `comercial\docs\2026-09-14-smoke-consolidado.md`, e a seção O atual ainda
  está pendente com o Eduardo.

## Como: o que já está decidido

Conferido no código em 02/11:

- **Lado da bolha:** `Message.vue` decide em `isBotOrAgentMessage`, que hoje dá direita a
  todo usuário. Na Equipe, compara o autor com o usuário atual; colega usa a variante cinza.
- **@ no editor:** `Editor.vue` só mostra `TagAgents` em nota privada. `TagAgents` lista
  todos os agentes e times. Na Equipe, a lista vem dos participantes.
- **@ no servidor:** `Messages::MentionService`, chamado pelo `NotificationListener` (o
  único que ouve a Equipe), exige mensagem privada e valida contra admins + membros da
  caixa. Ramo da Equipe: aceita mensagem pública, valida contra participantes e pula
  `add_mentioned_users_as_participants` (numa corrida com remoção, recriaria o participante
  com `last_seen_at` nulo). O serviço
  roda antes do aviso comum, cujo `already_notified?` já evita notificação dupla, e
  `TIPOS_AVISO` em `stores/equipe.js` já inclui `conversation_mention`.
- **Reações:** em `content_attributes` da mensagem, com trava da linha ao gravar, em
  endpoint em `ramon_equipe` com lista fechada dos seis emojis. O `message.updated` nativo
  já leva a mudança aos participantes. Sem tabela nova.
- **Vistos:** endpoint de participantes em `ramon_equipe` (id, nome, foto, `last_seen_at`)
  e novo evento de cable emitido em `Ramon::Equipe.marcar_lida`, só quando havia mensagem
  de colega não lida (a marca sempre avança, então comparar só a data não filtra nada), para
  os mesmos destinatários do `conversation_agents`.
- **Selo @ na lista:** campo próprio, calculado por pessoa no jbuilder da conversa e
  acendido no navegador ao chegar mensagem que me marca, junto de `naoLidaEquipe`. O
  `ADD_MESSAGE` só copia `unread_count`, então precisa levar o campo novo. O broadcast é igual
  para todos e não pode carregar esse campo. Conferir também o `unread_count` do
  `EventDataPresenter`: `push_data` o remove na Equipe (`RamonEventData`), e nenhum evento novo
  pode reintroduzi-lo zerado, porque `UPDATE_CONVERSATION` o espalharia.
- **Responder:** valer para a Equipe em dois pontos: `inboxSupportsReplyTo` em
  `MessagesView.vue` (menu) e `shouldShowReplyToMessage` em `ReplyBox.vue` (citação na caixa
  de escrever). Autor da citação em `bubbles/Base.vue`.
- **Canais externos da marcação:** e-mail e push de menção só chegam a quem ligou isso no
  perfil (padrão de conta nova é desligado). Sem mudança; registrar no ADR 0011.

## O que fica para quem implementa

- Formato do token de `@todos`. A regex de `shared/helpers/markdownIt/link.js` só aceita
  `user|team`; `@todos` precisa renderizar como marcação nos dois lados e nunca chegar cru.
- Schema do editor para a mensagem pública da Equipe carregar o nó de marcação (hoje só o
  formato de nota privada o tem).
- Como ramificar os componentes: `v-if` nos nativos ou componente próprio. Preferir o que
  menos diverge do Chatwoot.
- Ordem e divisão dos PRs. Regime: merge contínuo, aprovação e deploy por pacote.
- Mensagens de atividade ("Fulano atribuiu…"): se aparecerem na Equipe, esconder.
- Testes: specs do `MentionService` (ramo Equipe e não regressão do ramo cliente), reação,
  apagar, evento de leitura e guard surdo; vitest do cálculo de lado e de vistos.

## Decisões tomadas pelo Claude (revisar)

- Sem papel de parede.
- Admin que não participa não pode ser marcado e vê os dois lados à esquerda.
- Na 1:1, o @ lista só a outra pessoa.
- Apagar só a própria mensagem, com exceção do admin que participa (item 8, não pedido, é
  correção).
- Na Equipe, conversa só conta como lida com a aba visível.
- 1:1 mostra o nome e a foto da outra pessoa (como no mockup).
- "Te marcou" pode sair do sino na mensagem seguinte; o selo `@` fica.
- Merge só depois da aprovação dos prints.
- Microfone mantido na caixa de escrever.
- Reação não gera aviso.
- Reações em `content_attributes`, sem tabela nova.
