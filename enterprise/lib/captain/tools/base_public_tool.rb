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
  def execute(tool_context, **params)
    inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    resultado = super
    registrar_execucao(tool_context, params, resultado, 'ok', inicio)
    resultado
  rescue StandardError => e
    registrar_execucao(tool_context, params, "#{e.class}: #{e.message}", 'erro', inicio)
    raise
  end

  private

  def registrar_execucao(tool_context, params, resultado, status, inicio)
    ::Captain::ToolRun.create!(
      account_id: @assistant&.account_id, assistant_id: @assistant&.id,
      conversation_id: tool_context&.state&.dig(:conversation, :id),
      lead_id: Integer(params[:lead_id].to_s, exception: false),
      # RubyLLM::Tool#name devolve "captain-tools-checar_prescricao"; a tela
      # mostra o id do catalogo (config/agents/tools.yml).
      tool_name: name.to_s.split('-').last, status: status,
      params: params.except(:lead_id).transform_values(&:to_s),
      resultado: resultado.to_s.truncate(::Captain::ToolRun::MAX_RESULTADO),
      duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio) * 1000).round
    )
  rescue StandardError => e
    Rails.logger.warn("Captain::ToolRun: nao registrou execucao de #{name} (#{e.class}: #{e.message})")
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
