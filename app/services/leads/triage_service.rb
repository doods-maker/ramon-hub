class Leads::TriageService
  VIABILITY_PATTERN = /viabilidade\s*[:\-]?\s*(alta|m[ée]dia|baixa)/i
  MAX_MESSAGES = 200

  def initialize(triage)
    @triage = triage
    @lead = triage.lead
    @agent = triage.triage_agent
  end

  def perform
    @triage.update!(status: 'running')
    source = build_source_text
    result = call_llm(source)
    @triage.update!(status: 'done', result: result.content, source_text: source,
                    viability: detect_viability(result.content), finished_at: Time.zone.now)
    record_usage(result)
  rescue StandardError => e
    mark_error(e)
  end

  private

  def mark_error(error)
    @triage.update!(status: 'error', error_message: error.message.truncate(1000))
  rescue StandardError => e
    Rails.logger.error(
      "TriageService: falha ao gravar erro da triage #{@triage.id}: #{e.message}"
    )
  end

  # ponytail: record_usage duplicado nos 2 services; extrair concern se surgir um 3º consumidor.
  def record_usage(result)
    @triage.increment!(:input_tokens, result.input_tokens.to_i)
    @triage.increment!(:output_tokens, result.output_tokens.to_i)
  end

  def call_llm(source)
    user_prompt = "Documento do caso para triagem:\n\n#{source}\n\n" \
                  'Faça a análise conforme suas instruções. Ao final, escreva em uma ' \
                  'linha isolada: "VIABILIDADE: alta" (ou media, ou baixa).'
    Ramon::LlmClient.complete(provider: @agent.provider, model: @agent.model,
                              system: @agent.system_prompt, user: user_prompt,
                              sensitive: @agent.sensitive)
  end

  def detect_viability(text)
    match = text.to_s.downcase.match(VIABILITY_PATTERN)
    return nil if match.blank?

    match[1].tr('éí', 'ei')
  end

  # Pseudonimizado (LGPD) — o source_text gravado é exatamente o que foi pro LLM.
  def build_source_text
    text = [lead_sheet, conversation_transcript].compact_blank.join("\n\n")
    Ramon::Pseudonymizer.mask(text, names: [@lead.name, @lead.contact&.name])
  end

  def lead_sheet
    parts = ["Lead: #{@lead.name}"]
    parts << "Benefício de interesse: #{@lead.benefit_type.name}" if @lead.benefit_type
    parts << "Tese: #{@lead.thesis.name}" if @lead.thesis
    parts << "Origem: #{@lead.source}" if @lead.source.present?
    parts.join("\n")
  end

  def conversation_transcript
    conversation = @lead.conversation
    return nil if conversation.blank?

    messages = conversation.messages.where(message_type: [:incoming, :outgoing], private: false)
                           .where.not(content: [nil, '']).order(:created_at).last(MAX_MESSAGES)
    return nil if messages.empty?

    lines = messages.map { |m| "#{m.incoming? ? 'Cliente' : 'Atendimento'}: #{m.content}" }
    "Conversa (WhatsApp/chat):\n#{lines.join("\n")}"
  end
end
