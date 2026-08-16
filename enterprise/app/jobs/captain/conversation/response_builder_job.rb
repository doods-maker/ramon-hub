class Captain::Conversation::ResponseBuilderJob < ApplicationJob
  include Captain::Conversation::V1ActionClassifier

  MAX_MESSAGE_LENGTH = 10_000
  retry_on ActiveStorage::FileNotFoundError, attempts: 3, wait: 2.seconds
  retry_on Faraday::BadRequestError, attempts: 3, wait: 2.seconds

  def perform(conversation, assistant)
    @conversation = conversation
    @inbox = conversation.inbox
    @assistant = assistant

    return unless conversation_pending?

    @copiloto_modo = Ramon::CopilotoModo.of(@conversation)
    return if @copiloto_modo == 'manual' # IA quieta: nem gasta LLM

    Current.executed_by = @assistant

    if captain_v2_enabled?
      generate_response_with_v2
    else
      generate_and_process_response
    end
  rescue ActiveStorage::FileNotFoundError, Faraday::BadRequestError => e
    handle_error(e)
    raise e
  rescue StandardError => e
    handle_error(e)
  ensure
    Current.executed_by = nil
  end

  private

  delegate :account, :inbox, to: :@conversation

  def generate_and_process_response
    message_history = collect_previous_messages
    @response = Captain::Llm::AssistantChatService.new(assistant: @assistant, conversation: @conversation).generate_response(
      message_history: message_history
    )
    classify_v1_response_action(message_history) if conversation_pending?
    process_response
  end

  def generate_response_with_v2
    @response = Captain::Assistant::AgentRunnerService.new(assistant: @assistant, conversation: @conversation).generate_response(
      message_history: collect_previous_messages
    )
    process_response
  end

  def process_response
    # Check V2 before V1: error_response can set both signals at once when HandoffTool
    # fired before the runner errored. V2 must win — running V1 on top would duplicate
    # OOO and re-dispatch the bot_handoff event.
    if v2_handoff_tool_fired?
      if conversation_pending?
        # HandoffTool flipped the flag without committing — its perform returned a
        # failure string (e.g. "Conversation not found") before bot_handoff! ran. Fall
        # back to a full V1 handoff so the customer still ends up with a human.
        process_v1_handoff
      else
        # HandoffTool already opened the conversation inside the agent loop. All that's
        # left is the customer-facing follow-up message.
        process_v2_handoff
      end
    elsif v1_handoff_requested?
      # V1 only signals via the response string — no state has been touched yet. If
      # the conversation isn't pending anymore, a human took over mid-run; bail out
      # rather than posting a stale handoff message on top of their reply.
      return unless conversation_pending?

      process_v1_handoff
    elsif conversation_pending?
      # Classifica ANTES da transação: o roundtrip do LLM (PilotoLogisticaService) não
      # pode ficar preso segurando lock de transaction aberta.
      @logistica_ok = Ramon::PilotoLogisticaService.logistica?(@response['response']) if @copiloto_modo == 'piloto_limitado'
      ActiveRecord::Base.transaction do
        create_messages
        Rails.logger.info("[CAPTAIN][ResponseBuilderJob] Incrementing response usage for #{account.id}")
        account.increment_response_usage
      end
    end
  end

  def collect_previous_messages
    @conversation
      .messages
      .where(message_type: [:incoming, :outgoing])
      .where(private: false)
      .map do |message|
      message_hash = {
        content: prepare_multimodal_message_content(message),
        role: determine_role(message)
      }

      # Include agent_name if present in additional_attributes
      message_hash[:agent_name] = message.additional_attributes['agent_name'] if message.additional_attributes&.dig('agent_name').present?

      message_hash
    end
  end

  def determine_role(message)
    message.message_type == 'incoming' ? 'user' : 'assistant'
  end

  def prepare_multimodal_message_content(message)
    Captain::OpenAiMessageBuilderService.new(message: message).generate_content
  end

  def v1_handoff_requested?
    legacy_v1_handoff_token? || classifier_v1_handoff_requested?
  end

  def classifier_v1_handoff_requested?
    @response['action'] == 'handoff'
  end

  def legacy_v1_handoff_token?
    @response['response'] == 'conversation_handoff'
  end

  def v2_handoff_tool_fired?
    @response['handoff_tool_called']
  end

  def process_v1_handoff
    I18n.with_locale(@assistant.account.locale) do
      Rails.logger.info(
        "[CAPTAIN][ResponseBuilderJob] V1 handoff requested for account=#{account.id} conversation=#{@conversation.display_id} " \
        "source=#{@response&.dig('action_source') || 'legacy'} reason=#{@response&.dig('action_reason')}"
      )
      create_handoff_message
      @conversation.bot_handoff!
      report_v1_handoff_not_executed if conversation_pending?
      send_out_of_office_message_if_applicable
    end
  end

  def process_v2_handoff
    # HandoffTool already ran bot_handoff! + OOO inside the agent loop. Preserve
    # waiting_since so this message doesn't clear the timestamp it left in place.
    I18n.with_locale(@assistant.account.locale) do
      create_handoff_message(preserve_waiting_since: true)
    end
  end

  def send_out_of_office_message_if_applicable
    # Campaign conversations should never receive OOO templates — the campaign itself
    # serves as the initial outreach, and OOO would be confusing in that context.
    return if @conversation.campaign.present?

    ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(@conversation)
  end

  def create_handoff_message(preserve_waiting_since: false)
    # Handoff é logística por definição (constraint global) — nunca vira rascunho
    # em piloto_limitado. Único call site (v1 e v2 passam por aqui), então o flag
    # é setado uma vez só, imediatamente antes da chamada.
    @enviando_handoff = true
    create_outgoing_message(
      @assistant.config['handoff_message'].presence || I18n.t('conversations.captain.handoff'),
      preserve_waiting_since: preserve_waiting_since
    )
  end

  def create_messages
    validate_message_content!(@response['response'])
    create_outgoing_message(@response['response'], agent_name: @response['agent_name'])
  end

  def validate_message_content!(content)
    raise ArgumentError, 'Message content cannot be blank' if content.blank?
  end

  def create_outgoing_message(message_content, agent_name: nil, preserve_waiting_since: false)
    # Onda C: o modo POR CONVERSA decide. Rascunho continua sendo o default e
    # também o fallback do flag global antigo (assistant.modo_rascunho?).
    # O `||` é belt-and-suspenders: `perform` sempre seta @copiloto_modo antes
    # de chegar aqui (hoje inalcançável), mas evita nil se algum caller futuro
    # (ex.: um teste chamando este método direto) pular esse passo.
    modo = @copiloto_modo || Ramon::CopilotoModo.of(@conversation)
    return create_draft_note(message_content) unless Ramon::CopilotoModo.piloto?(modo)

    if modo == 'piloto_limitado' && !@enviando_handoff && !@logistica_ok
      # @logistica_ok é calculado ANTES da transação em process_response (fora do
      # ActiveRecord::Base.transaction, pra tirar o roundtrip do LLM de dentro do
      # lock). nil (caller inesperado, ex.: teste chamando este método direto) cai
      # no `!` e vira fail-safe: trata como NÃO logística, ou seja, rascunho.
      return create_draft_note(message_content)
    end

    additional_attrs = {}
    additional_attrs[:agent_name] = agent_name if agent_name.present?

    @conversation.messages.create!(
      message_type: :outgoing,
      account_id: account.id,
      inbox_id: inbox.id,
      sender: @assistant,
      content: message_content,
      additional_attributes: additional_attrs,
      content_attributes: { 'ramon_piloto' => { 'modo' => modo, 'em' => Time.zone.now.iso8601 } },
      preserve_waiting_since: preserve_waiting_since
    )
  end

  # ramon: agente de atendimento com humano no meio (Fatia 2 da area de IA).
  # Com o modo rascunho ligado no assistente, NADA que ele escreve chega ao
  # cliente: a resposta vira nota privada no proprio painel da conversa, com o
  # mesmo prefixo RASCUNHO do resto do hub, e quem revisa e envia e o atendente.
  def create_draft_note(message_content)
    @conversation.messages.create!(message_type: :outgoing, private: true, account_id: account.id,
                                   inbox_id: inbox.id, sender: @assistant,
                                   content: "RASCUNHO (revisar antes de enviar):\n#{message_content}")
  end

  def handle_error(error)
    log_error(error)
    @response ||= {}
    @response['action_source'] ||= 'error'
    @response['action_reason'] ||= error_action_reason(error)
    process_v1_handoff if conversation_pending?
    true
  end

  def log_error(error)
    ChatwootExceptionTracker.new(error, account: account).capture_exception
  end

  def error_action_reason(error)
    error.class.name.underscore.tr('/', '_')
  end

  def captain_v2_enabled?
    account.feature_enabled?('captain_integration_v2')
  end

  def report_v1_handoff_not_executed
    error = StandardError.new("Captain V1 handoff requested but conversation #{@conversation.display_id} is still pending")
    ChatwootExceptionTracker.new(error, account: account).capture_exception
    Rails.logger.error(
      "[CAPTAIN][ResponseBuilderJob] V1 handoff requested but not executed for account=#{account.id} " \
      "conversation=#{@conversation.display_id}"
    )
  end

  def conversation_pending?
    status = Conversation.uncached { Conversation.where(id: @conversation.id).pick(:status) }
    status == 'pending' || status == Conversation.statuses[:pending]
  end
end
