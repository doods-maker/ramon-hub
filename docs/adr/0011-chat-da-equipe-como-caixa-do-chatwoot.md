# Chat da equipe como caixa do Chatwoot (sai o módulo próprio)

Substitui a decisão de 02/10 ("chat em módulo próprio, isolado das conversas do
Chatwoot"), entregue no PR #303.

Em 31/10, com o #303 no ar, o Eduardo decidiu que o chat interno fica **dentro
da tela de Conversas**, como mais uma caixa: **Equipe**. O ganho é tudo o que a
conversa nativa já tem e o módulo próprio não tinha (anexo, foto, áudio, busca,
notas, menções, tempo real, sino). O módulo do #303 saiu inteiro (tabelas
`ramon_chat_*`, vazias em produção, apagadas por migração).

Como fica:

- **Caixa:** `Channel::Api` sem webhook, marcada por `inboxes.equipe`. Ninguém é
  membro da caixa; ela é listada para todos.
- **Conversas:** Geral (todos os usuários), uma por time (membros do time) e as
  1:1, abertas sob demanda. Cada conversa tem um contato sintético
  (`additional_attributes.equipe = true`, sem telefone/e-mail — fora da lista de
  contatos), achado pelo `source_id` (`equipe-geral`, `equipe-time-<id>`,
  `equipe-1a1-<a>-<b>`).
- **Quem vê:** quem participa (`conversation_participants`) — Geral, os times
  dele, as 1:1 dele — e administradores (tudo, inclusive 1:1; avisado na tela).
  Mesmo desenho do ADR 0004: o agente fica fora da caixa, então caminho
  esquecido falha para o lado seguro. Os participantes são ressincronizados no
  commit de `TeamMember` e `AccountUser` (`Ramon::Equipe.sincronizar`).
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

Limites conhecidos: time apagado só some do canal na próxima sincronização
(qualquer mudança de time ou o comando do deploy); a busca do contato por nome
acha "Geral"/"Setor …" (sem efeito: não é lead nem cliente); a conversa da
Equipe não entra em "Todas" — só dentro da caixa.
