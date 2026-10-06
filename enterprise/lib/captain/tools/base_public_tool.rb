require 'agents'

class Captain::Tools::BasePublicTool < Agents::Tool
  def initialize(assistant)
    @assistant = assistant
    super()
  end

  def active?
    # Public tools are always active
    true
  end

  def permissions
    # Override in subclasses to specify required permissions
    # Returns empty array for public tools (no permissions required)
    []
  end

  # ramon: log auditavel da tela Execucoes (Fatia 3 da area de IA). O
  # instrumentation nativo do Captain so grava com OpenTelemetry ligado, e aqui
  # nao esta — sem isto nao ha o que auditar. Registrar nunca pode derrubar a
  # tool: falha de gravacao vira linha de log e o resultado segue.
  # ramon: tool que estoura NAO pode derrubar a resposta inteira. O runner do
  # agente devolve output nil quando uma tool levanta, o job trata isso como
  # resposta em branco e transfere a conversa — foi o que aconteceu com o
  # faq_lookup, que depende de embeddings da OpenAI (esta instalacao so tem
  # DeepSeek). O erro vira String pro LLM, que segue a conversa sem a tool, e
  # fica registrado com status 'erro' na tela Execucoes.
  ERRO_NA_TOOL = 'A ferramenta falhou agora. Siga sem ela e avise que esse dado nao pode ser consultado no momento.'.freeze

  # ramon: modo teste (Casos de teste da IA). Com source 'teste' no estado, so
  # as consultas rodam; o resto devolve o que faria, sem executar nada.
  SOURCE_TESTE = 'teste'.freeze

  def self.teste?(tool_context)
    tool_context&.state&.dig(:source).to_s == SOURCE_TESTE
  end

  def self.simulacao(nome, params)
    "[TESTE] faria #{nome}(#{params.map { |chave, valor| "#{chave}: #{valor}" }.join(', ')})"
  end

  def execute(tool_context, **params)
    inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    resultado = escreve_em_teste?(tool_context) ? self.class.simulacao(id_catalogo, params) : super
    registrar_execucao(tool_context, params, resultado, 'ok', inicio)
    resultado
  rescue StandardError => e
    Rails.logger.error("#{self.class.name}: falhou (#{e.class}: #{e.message})")
    registrar_execucao(tool_context, params, "#{e.class}: #{e.message}", 'erro', inicio)
    ERRO_NA_TOOL
  end

  private

  # RubyLLM::Tool#name devolve "captain-tools-checar_prescricao"; o catalogo
  # (config/agents/tools.yml) e as telas usam o id.
  def id_catalogo
    name.to_s.split('-').last
  end

  # Ferramenta fora do catalogo conta como escrita: no teste, na duvida, nao executa.
  def escreve_em_teste?(tool_context)
    return false unless self.class.teste?(tool_context)

    ::Captain::Assistant.built_in_agent_tools.find { |tool| tool[:id] == id_catalogo }&.dig(:nivel) != 'consulta'
  end

  def registrar_execucao(tool_context, params, resultado, status, inicio)
    ::Captain::ToolRun.create!(
      account_id: @assistant&.account_id, assistant_id: @assistant&.id, **origem(tool_context),
      lead_id: Integer(params[:lead_id].to_s, exception: false),
      tool_name: id_catalogo, status: status,
      params: params.except(:lead_id).transform_values(&:to_s),
      resultado: resultado.to_s.truncate(::Captain::ToolRun::MAX_RESULTADO),
      duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio) * 1000).round
    )
  rescue StandardError => e
    Rails.logger.warn("Captain::ToolRun: nao registrou execucao de #{name} (#{e.class}: #{e.message})")
  end

  # source separa playground/teste do atendimento real nas telas.
  def origem(tool_context)
    state = tool_context&.state || {}
    { conversation_id: state.dig(:conversation, :id), source: state[:source]&.to_s }
  end

  def account_scoped(model_class)
    model_class.where(account_id: @assistant.account_id)
  end

  def find_conversation(state)
    conversation_id = state&.dig(:conversation, :id)
    return nil unless conversation_id

    account_scoped(::Conversation).find_by(id: conversation_id)
  end

  def find_contact(state)
    contact_id = state&.dig(:contact, :id)
    return nil unless contact_id

    account_scoped(::Contact).find_by(id: contact_id)
  end

  def log_tool_usage(action, details = {})
    Rails.logger.info do
      "#{self.class.name}: #{action} for assistant #{@assistant&.id} - #{details.inspect}"
    end
  end
end
