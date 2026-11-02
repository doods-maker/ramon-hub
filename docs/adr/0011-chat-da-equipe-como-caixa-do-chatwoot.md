# Chat da equipe como caixa do Chatwoot (sai o módulo próprio)

Atualizado em 02/11/2026 (Equipe com cara de WhatsApp: PRs #307, #309 e pacote 3+4; revisão final: só participantes + admin e lista permitida).

Substitui a decisão de 02/10 ("chat em módulo próprio, isolado das conversas do
Chatwoot"), entregue no PR #303.

Em 31/10, com o #303 no ar, o Eduardo decidiu que o chat interno fica **dentro
da tela de Conversas**, como mais uma caixa: **Equipe**. O ganho é tudo o que a
conversa nativa já tem e o módulo próprio não tinha (anexo, foto, áudio, notas,
tempo real, sino). O módulo do #303 saiu inteiro (tabelas
`ramon_chat_*`, vazias em produção, apagadas por migração).

Como fica:

- **Caixa:** `Channel::Api` sem webhook, marcada por `inboxes.equipe`. Ninguém é
  membro da caixa; ela é listada para todos.
- **Conversas:** Geral (todos os usuários), uma por time (membros do time) e as
  1:1, abertas sob demanda. Cada conversa tem um contato sintético
  (`additional_attributes.equipe = true`, sem telefone/e-mail — fora da lista de
  contatos), achado pelo `source_id` (`equipe-geral`, `equipe-time-<id>`,
  `equipe-1a1-<a>-<b>`).
- **Quem vê:** só quem participa (`conversation_participants`) — Geral, os times
  dele, as 1:1 dele — e administradores (tudo, inclusive 1:1; avisado na tela).
  **Atribuição, time e membro de caixa não dão acesso** (decisão de 02/11): nem na
  lista, nem no `GET` da conversa, nem no tempo real, nem na busca, nem no aviso de
  mensagem nova. Os participantes são ressincronizados no commit de `TeamMember` e
  `AccountUser` (`Ramon::Equipe.sincronizar`).
- **O que o HTTP aceita numa conversa da Equipe:** uma lista permitida, em um lugar só
  (`Ramon::Equipe::HTTP_PERMITIDO`), checada em `Conversations::BaseController` e
  `ConversationsController`: abrir, ler, marcar lida, digitar, enviar, apagar a própria,
  anexos, participantes (só leitura) e etiquetas (só leitura, a tela busca ao abrir).
  Todo o resto é 403, inclusive para admin: atribuir, etiquetar, status, prioridade, mudar
  participante, tradução, status de mensagem, copiloto e `transcript` (mandaria uma 1:1 a
  qualquer e-mail). Macro e ação em massa que incluem conversa da Equipe também são
  recusadas, e não se cria conversa na caixa pela API. O guard é só do HTTP:
  `Ramon::Equipe.sincronizar` continua usando `conversation.open!`.
- **Hub surdo:** um guard só, no `AsyncDispatcher`: evento de conversa,
  mensagem, contato ou caixa da Equipe vai apenas ao `NotificationListener`
  (aviso nativo a quem participa). Lead, fluxos, agente `@claude`, Captain,
  automações, webhooks, CSAT e relatórios não ouvem. Caixa criada sem
  atribuição automática e sem lead; auto-resolver da conta pula a Equipe; as
  views do BI só contam conversa com lead ou com mensagem de cliente, então a
  Equipe já fica fora.
- **Não-lida por pessoa:** o Chatwoot só conta mensagem de cliente e tem um
  `agent_last_seen_at` por conversa. Na Equipe a não-lida é a mensagem de
  colega depois de `conversation_participants.last_seen_at` (calculada por
  quem pede; o broadcast não leva `unread_count`).

Alternativas descartadas:

- **Manter o módulo próprio:** refaria anexo, áudio, busca e notificação.
- **Pessoas como membros da caixa + esconder o resto:** cada caminho esquecido
  vazaria 1:1 alheia (mesmo argumento do ADR 0004).
- **Visibilidade do setor por `team_id`:** ligaria a atribuição automática do
  time e não dá a não-lida/aviso por pessoa; participantes resolvem os dois.

Portas laterais fechadas: a API pública de caixa Api recusa a Equipe (o
`source_id` dos contatos é previsível) e abrir o painel do lead numa conversa
da Equipe nunca cria lead.

Limites conhecidos:

- **Não adicionar colaboradores (membros) na caixa Equipe** nas configurações. Agora é
  seguro por padrão: ser membro não dá acesso a conversa de que a pessoa não participa.
  Mas não serve para nada e confunde quem olha a tela de caixas.
- Menção (@): na Equipe só marca participantes da conversa e **nunca adiciona
  ninguém** (ramo próprio no `MentionService`); `@todos` só em grupo. Vale
  também em mensagem pública, só nesta caixa. O aviso "te marcou" chega a
  quem ligou e-mail/push de menção no perfil; os demais veem o sino e o selo.
- **Admin de fora é só leitura:** vê tudo, mas não escreve, não digita e não
  vê ✓ (substitui "quem vê também responde" para esse caso). Apagar: só o
  autor, ou admin que participa.
- ✓✓ por `conversation_participants.last_seen_at`; reações em
  `content_attributes` da mensagem (👍 ❤️ 😂 😮 😢 🙏), sem som e sem notificação.
- Cada mensagem vira notificação no sino de quem participa (o toast de 6 s é o
  aviso discreto); e-mail/push só se a pessoa ligar "conversa de que participo".
- O evento de contato novo vai a toda a conta: o nome "Ana e Bia" revela que a
  1:1 existe (não o conteúdo). A busca de contato acha esses nomes.
- Relatórios ao vivo e filtros avançados/pastas do Chatwoot contam as conversas
  da Equipe como abertas; o BI (Metabase) não.
- Time apagado só some do canal na próxima sincronização (qualquer mudança de
  time ou o comando do deploy); nomes de time/pessoa renomeados não mudam o
  nome da conversa. "Marcar como não lida" é recusado na Equipe.
- Copiloto e tarefas de IA recusam conversa da Equipe no servidor (403). O painel
  global do copiloto segue respondendo com uma conversa da Equipe aberta, mas sem ler a
  conversa (`CopilotMessage#enqueue_response_job` tira o `conversation_id`).
