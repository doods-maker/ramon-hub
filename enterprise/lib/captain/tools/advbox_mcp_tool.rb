# Ponte entre o Copiloto e o servidor MCP do AdvBox (Ramon::AdvboxMcpService):
# a tool filha declara `mcp_tool 'advbox_x'` e herda descricao, parametros e
# execucao da ferramenta homonima do MCP — a mesma que os projetos Cowork usam.
# Por padrao so aceita ferramentas de LEITURA; escrita so pela filha
# AdvboxMcpEscritaTool, que exige confirmacao do humano.
class Captain::Tools::AdvboxMcpTool < Captain::Tools::BasePublicTool
  # ponytail: teto burro de caracteres, igual ao consultar_dossie_advbox.
  MAX_CHARS = 40_000

  class << self
    attr_reader :mcp_nome

    def escrita?
      false
    end

    def mcp_tool(nome)
      raise ArgumentError, "#{nome} grava no AdvBox — so leitura por aqui" if Ramon::AdvboxMcpService::ESCRITAS.include?(nome) && !escrita?

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
    chamar_mcp(coagir(params.compact))
  end

  private

  def chamar_mcp(args)
    log_tool_usage(self.class.mcp_nome, { campos: args.keys })
    resposta = Ramon::AdvboxMcpService.call_tool('params' => { 'name' => self.class.mcp_nome, 'arguments' => args })
    texto = resposta[:content].first[:text]
    texto.length > MAX_CHARS ? "#{texto[0, MAX_CHARS]} [resultado truncado]" : texto
  end

  # O LLM manda numero/booleano como string; os fetchers do MCP repassam o valor cru.
  def coagir(params)
    props = Ramon::AdvboxMcpService::TOOLS.find { |t| t[:name] == self.class.mcp_nome }[:inputSchema][:properties]
    params.to_h do |chave, valor|
      case props.dig(chave.to_sym, :type)
      when 'integer' then valor = Integer(valor.to_s, exception: false) || valor
      when 'boolean' then valor = valor.to_s == 'true' if valor.is_a?(String)
      end
      [chave.to_s, valor]
    end
  end
end
