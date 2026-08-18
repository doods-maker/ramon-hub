# Escrita no AdvBox pelo Copiloto, em dois tempos: sem `codigo` a tool NAO grava —
# devolve o resumo do que vai gravar e um codigo (hash dos dados); o Copiloto
# mostra o resumo ao humano e so chama de novo, com o codigo, depois do "ok".
# O codigo amarra os dados: mudou qualquer campo, o codigo nao confere e nada
# e gravado. Toda chamada (previa e gravacao) fica na tela Execucoes.
#
# ponytail: a confirmacao e o LLM relatando o "ok" do humano — nao ha clique
# fisico como no Cockpit (o Copiloto do Escritorio roda no Playground, sem
# conversa/lead pra pendurar uma CopilotSuggestion). Se algum dia gravar sem
# pedir, o upgrade e guardar a previa em Captain::ToolRun e exigir mensagem
# humana posterior contendo o codigo.
class Captain::Tools::AdvboxMcpEscritaTool < Captain::Tools::AdvboxMcpTool
  # Processo e financeiro ficam de fora de proposito (decisao do agente-hub v1).
  PERMITIDAS = %w[advbox_criar_tarefa advbox_criar_movimentacao advbox_criar_cliente].freeze
  AVISO = ' NAO grava na primeira chamada: devolve o resumo e um codigo. Mostre o resumo ao humano, ' \
          'peca confirmacao e SO ENTAO chame de novo com o mesmo conteudo e o codigo. IDs vem de configuracoes_advbox.'.freeze

  class << self
    def escrita?
      true
    end

    def mcp_tool(nome)
      raise ArgumentError, "#{nome} nao e escrita permitida ao Copiloto" unless PERMITIDAS.include?(nome)

      super
      description "#{description}#{AVISO}"
      param :codigo, type: 'string', desc: 'Codigo devolvido pela previa, DEPOIS que o humano confirmou. Sem ele, so mostra o resumo.',
                     required: false
    end
  end

  def perform(_tool_context, codigo: nil, **params)
    args = coagir(params.compact)
    esperado = codigo_de(args)
    return previa(args, esperado) if codigo.blank?
    return 'Codigo nao confere com esses dados — mostre o resumo de novo e peca nova confirmacao.' unless codigo.to_s.strip == esperado

    "Gravado no AdvBox (#{self.class.mcp_nome}): #{chamar_mcp(args)}"
  end

  private

  def previa(args, codigo)
    resumo = args.map { |k, v| "#{k}: #{v}" }.join('; ')
    "NADA foi gravado ainda. Vou gravar no AdvBox (#{self.class.mcp_nome}) → #{resumo}. " \
      "Mostre isso ao humano e peca confirmacao; quando ele disser ok, chame de novo com codigo=#{codigo}."
  end

  def codigo_de(args)
    Digest::SHA1.hexdigest("#{@assistant&.id}|#{self.class.mcp_nome}|#{args.sort.to_json}")[0, 6]
  end
end
