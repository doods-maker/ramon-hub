# 0014. Aprovações da esteira pelo hub

Data: 02/11/2026. Pedido do Eduardo: responder às permissões da esteira de qualquer PC, sem abrir o terminal.

## Decisão

Um hook `PermissionRequest` na esteira abre o pedido no hub e espera a resposta. A tela Agentes mostra os pedidos acima do
painel, com Aprovar e Negar.

- **Quem decide é só a tela:** responder exige sessão do hub e estar em `RAMON_PAINEL_AGENTES_EMAILS`. O token do hook
  (`RAMON_ESTEIRA_APROVACOES_TOKEN`) só cria pedido e lê status, então vazar esse token não aprova nada.
- **O terminal continua sendo a saída:** se o hub não responder, o hook sai sem decidir e o pedido segue o fluxo normal
  do Claude Code. Comportamento a confirmar no primeiro teste, porque a documentação não o define para este evento.
- **Negar não para a sessão:** o hook devolve a negação com mensagem e `interrupt: false`, para o chefe seguir o caso.
- **Entrada apagada ao decidir:** a entrada traz dado de cliente. Ela some ao decidir, e fica só quem decidiu, o quê e quando.
- **Regra `deny` continua valendo:** a aprovação do hub não sobrepõe uma regra `deny` da esteira.

## Consequências

- Pedido sem resposta espera até 12 horas e depois volta para o terminal. Com a vigília ligada, o caso fica parado, como
  já ficava no terminal.
- O push pelo ntfy não leva caso, ferramenta nem dado de cliente, porque o tópico é público.
- A tela consulta os pedidos a cada 5 segundos enquanto está aberta, e só para quem tem acesso.
