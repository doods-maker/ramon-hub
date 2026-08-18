# Leitura pura no AdvBox via MCP: Dados de um processo (etapa, responsavel, clientes, honorarios) sem puxar o dossie inteiro.
class Captain::Tools::ProcessoAdvboxTool < Captain::Tools::AdvboxMcpTool
  mcp_tool 'advbox_processo'
end
