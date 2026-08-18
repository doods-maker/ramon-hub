# Leitura pura no AdvBox via MCP: Busca contatos/clientes por nome, CPF, telefone ou cidade.
class Captain::Tools::BuscarClienteAdvboxTool < Captain::Tools::AdvboxMcpTool
  mcp_tool 'advbox_buscar_clientes'
end
