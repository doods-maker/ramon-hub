# Ponte entre o Copiloto e o servidor MCP do AdvBox (Ramon::AdvboxMcpService):
# a tool filha declara `mcp_tool 'advbox_x'` e herda descricao, parametros e
# execucao da ferramenta homonima do MCP — a mesma que os projetos Cowork usam.
# So aceita ferramentas de LEITURA: o Copiloto nao grava no AdvBox por aqui
# (escrita segue o padrao sugestao → humano aprova).
class Captain::Tools::AdvboxMcpTool < Captain::Tools::BasePublicTool
  # ponytail: teto burro de caracteres, igual ao consultar_dossie_advbox.
  MAX_CHARS = 40_000

  class << self
    attr_reader :mcp_nome

    def mcp_tool(nome)
      raise ArgumentError, "#{nome} grava no AdvBox — so leitura por aqui" if Ramon::AdvboxMcpService::ESCRITAS.include?(nome)

      schema = Ramon::AdvboxMcpService::TOOLS.find { |t| t[:name] == nome } or raise ArgumentError, "MCP sem #{nome}"
      @mcp_nome = nome
      description schema[:description]
      obrigatorios = schema[:inputSchema][:required].map(&:to_s)
      schema[:inputSchema][:properties].each do |chave, prop|
        param chave, type: prop[:type], desc: prop[:description] || chave.to_s.tr('_', ' '), required: obrigatorios.include?(chave.to_s)
      end
    end
  end

  def perform(_tool_context, **params)
    args = coagir(params.compact)
    log_tool_usage(self.class.mcp_nome, { campos: args.keys })
    resposta = Ramon::AdvboxMcpService.call_tool('params' => { 'name' => self.class.mcp_nome, 'arguments' => args })
    texto = resposta[:content].first[:text]
    texto.length > MAX_CHARS ? "#{texto[0, MAX_CHARS]} [resultado truncado]" : texto
  end

  private

  # O LLM manda numero como string; os fetchers do MCP repassam o valor cru.
  def coagir(params)
    props = Ramon::AdvboxMcpService::TOOLS.find { |t| t[:name] == self.class.mcp_nome }[:inputSchema][:properties]
    params.to_h do |chave, valor|
      valor = Integer(valor.to_s, exception: false) || valor if props.dig(chave.to_sym, :type) == 'integer'
      [chave.to_s, valor]
    end
  end
end
