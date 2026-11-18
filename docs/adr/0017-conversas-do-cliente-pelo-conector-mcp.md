# 0017. Conversas do cliente pelo conector MCP

Data: 18/11/2026. Pedido do Eduardo (com o Paulo, da CX): relatório pós-contato feito pelo Claude da recepção (skill
`/relatorio-pos-contato` do plugin coworks), com dúvidas, reclamações e risco de desistência.

## Decisão

O MCP do hub (`/public/api/v1/mcp`, o mesmo conector do AdvBox no Cowork) ganha duas ferramentas, servidas por
`Ramon::ConversasDoCliente`:

- `hub_conversas_cliente`: conversas do cliente achado pelo celular (qualquer grafia BR) ou CPF. Janela padrão de
  30 dias, com mensagens do cliente e do escritório, áudios transcritos e **notas privadas** da equipe, e os casos
  (leads) do cliente.
- `hub_criar_nota`: grava o relatório como nota privada na conversa. A skill mostra o texto e pede o OK antes.

Invariantes: a caixa Equipe nunca entra, nem na leitura nem na escrita (ADR 0011); a senha sai mascarada
(`Message#content_for_llm`); a conta é a do escritório (`RAMON_LEAD_CAPTURE_ACCOUNT_ID`).

## Consequências (aceitas pelo Eduardo em 18/11/2026)

- **O token do MCP é único e compartilhado.** Quem tem o conector (associados, controladoria, recepção) lê o WhatsApp de
  qualquer cliente, inclusive as conversas atribuídas a outra advogada. É uma exceção ao "cada um vê o seu" da ADR 0004
  para esse canal. O fim dela é o token por pessoa, já pendente na rotação do `RAMON_MCP_TOKEN`.
- **Conversas e notas saem do hub sem pseudonimização**, para o claude.ai, como já acontece com os dados do AdvBox pelo
  mesmo conector. Pode haver dado de saúde no que o cliente escreve. A ADR 0007 continua valendo para a memória do
  contato, que é outra coisa.
- O cliente orgânico que só existe no AdvBox volta com `contatos` vazio: a skill segue só com o relato e o AdvBox.
