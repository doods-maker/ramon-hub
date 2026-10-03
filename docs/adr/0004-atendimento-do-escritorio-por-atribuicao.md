# Atendimento do escritório por atribuição (sem menu)

Substitui o roteamento do ADR 0003 (o número do escritório na API oficial,
atendido no hub, continua valendo).

Escrevendo os POPs do escritório, decidimos (2026-10-02) que **a Recepção faz a
triagem**: toda conversa nova da caixa do escritório cai nela, e é ela quem
**atribui** ao advogado certo ou ao time da Controladoria. Sai o menu de botões
da Portaria (o cliente escolhendo o setor) e sai o rodízio entre advogados.

Cada pessoa vê só o que é dela:

- **Recepção** é membro da caixa → vê todas as conversas dela.
- **Advogado** não é membro da caixa → vê só as conversas atribuídas a ele.
- **Controladoria** não é membro da caixa, mas é do time `controladoria` → vê a
  fila inteira do time.
- Administradores veem tudo, como sempre.

Como isso é feito no fork: a visibilidade do agente passou a ser "caixas de que é
membro **ou** conversa atribuída a ele **ou** conversa de um time dele"
(`PermissionFilterService`, `ConversationPolicy`, tempo real no
`ActionCableListener`). Na caixa do escritório (`inboxes.portaria_enabled`, nome
mantido para não migrar) qualquer usuário pode ser escolhido na atribuição, e a
caixa é listada para todos, porque a tela de resposta precisa dos dados da
caixa (janela de 24h, modelos).

Alternativas descartadas:

- **Papéis personalizados do Chatwoot** ("só conversas atribuídas"): já fazem
  isso, mas são recurso pago da edição Enterprise.
- **Advogados como membros da caixa + esconder o resto**: cada caminho esquecido
  (tempo real, notificação de conversa nova, busca, contadores) vazaria conversa
  alheia. Com o advogado fora da caixa, o caminho esquecido falha para o lado
  seguro: ele deixa de ver algo, nunca vê demais.

Limites conhecidos: a busca global e os contadores de não lidas do advogado não
incluem as conversas da caixa do escritório; quem perde a atribuição só vê a
conversa sumir da lista ao recarregar.
