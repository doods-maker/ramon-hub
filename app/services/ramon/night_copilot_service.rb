# Copiloto noturno (mock 4b): de madrugada, varre os leads parados do funil e
# pede ao LLM UMA análise por lead — rascunho de mensagem, sugestão de mover
# etapa ou alerta. Tudo vira CopilotSuggestion pendente pro humano aprovar de
# manhã no Cockpit. NADA é enviado ao cliente por aqui.
class Ramon::NightCopilotService
  MAX_MESSAGES = 200
  PROVIDER = 'deepseek'.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o copiloto noturno de um escritório de advocacia previdenciária no Brasil.
    Receberá a ficha e a conversa de UM lead parado no funil comercial. Analise e devolva
    APENAS um JSON válido (sem markdown, sem comentários) com exatamente este formato:
    {"tipo": "draft" | "move_stage" | "alert", "texto": "...", "etapa_sugerida": "...", "justificativa": "..."}

    Como escolher o tipo:
    - "alert": a conversa tem risco real (menção a concorrente, desistência, prazo estourando).
      Preencha só "justificativa" (1-2 frases, direto ao ponto).
    - "move_stage": a conversa mostra claramente que o lead pertence a OUTRA etapa da lista
      fornecida. Preencha "etapa_sugerida" com o nome EXATO de uma etapa da lista e "justificativa".
    - "draft": caso contrário, escreva em "texto" uma mensagem de retomada de WhatsApp
      (2 a 4 frases, tom de médico de confiança, sem juridiquês) e a "justificativa".

    Regras obrigatórias:
    - NUNCA prometa resultado do caso nem prazo do INSS (regra da OAB).
    - Não invente fatos que não estejam na conversa.
    - Se precisar chamar o cliente pelo nome, escreva exatamente [nome].
  PROMPT

  def initialize(account:)
    @account = account
  end

  def perform
    batch = eligible_leads
    created = batch.count { |lead| suggest_for(lead) }
    Rails.logger.info("NightCopilotService: conta #{@account.id} — #{batch.size} leads revisados, #{created} sugestões")
    created
  end

  private

  def limit
    ENV.fetch('RAMON_NIGHT_COPILOT_LIMIT', '15').to_i
  end

  # Idempotência: lead com sugestão pendente não entra de novo.
  def eligible_leads
    Ramon::LeadRadar.stalled_leads(@account)
                    .where.not(id: @account.copilot_suggestions.pending.select(:lead_id))
                    .first(limit)
  end

  # LLM falhou ou devolveu lixo = pula o lead, não derruba o lote.
  def suggest_for(lead)
    parsed = analysis_for(lead)
    return false if parsed.blank?

    @account.copilot_suggestions.create!(
      lead: lead, kind: parsed['tipo'], status: 'pending', run_at: Time.current,
      payload: parsed.merge(lead_snapshot(lead))
    )
    true
  end

  def analysis_for(lead)
    result = Ramon::LlmClient.complete(provider: PROVIDER,
                                       model: ENV.fetch('RAMON_COPILOT_MODEL', 'deepseek-chat'),
                                       system: SYSTEM_PROMPT, user: user_prompt(lead))
    parse_analysis(lead, result.content)
  rescue StandardError => e
    Rails.logger.warn("NightCopilotService: LLM falhou p/ lead #{lead.id} (#{e.class}: #{e.message}) — pulando")
    nil
  end

  # Valida a saída: JSON inválido ou tipo desconhecido = descarta.
  def parse_analysis(lead, content)
    parsed = JSON.parse(content.to_s.sub(/\A```(?:json)?\s*/, '').sub(/```\s*\z/, ''))
    return nil unless parsed.is_a?(Hash) && CopilotSuggestion::KINDS.include?(parsed['tipo'])

    parsed['texto'] = restore_name(lead, parsed['texto']) if parsed['texto'].present?
    parsed.slice('tipo', 'texto', 'etapa_sugerida', 'justificativa')
  rescue JSON::ParserError
    Rails.logger.warn("NightCopilotService: JSON inválido p/ lead #{lead.id} — descartando")
    nil
  end

  # snapshot mínimo pro card não depender de join na hora de listar
  def lead_snapshot(lead)
    { 'lead_name' => lead.name, 'stage_name' => lead.lead_stage&.name, 'days_stalled' => days_stalled(lead) }
  end

  # Pseudonimizado (LGPD, mesmo padrão do Copilot): o texto só sai daqui mascarado.
  def user_prompt(lead)
    text = [lead_sheet(lead), transcript(lead.conversation)].compact_blank.join("\n\n")
    Ramon::Pseudonymizer.mask(text, names: [lead.name, lead.contact&.name])
  end

  def lead_sheet(lead)
    ["Lead parado há #{days_stalled(lead)} dias sem avanço.",
     "Etapa atual: #{lead.lead_stage&.name || 'não informada'}.",
     "Tese/benefício: #{lead.thesis&.name || lead.benefit_type&.name || 'não informado'}.",
     "Etapas disponíveis no funil: #{stage_names.join(', ')}."].join("\n")
  end

  def stage_names
    @stage_names ||= @account.lead_stages.where(is_won: false, is_lost: false).order(:position).pluck(:name)
  end

  def days_stalled(lead)
    return 0 if lead.stage_entered_at.blank?

    (Time.zone.today - lead.stage_entered_at.to_date).to_i
  end

  # ponytail: espelha FollowUpDraftService#transcript; extrair helper comum se surgir um 5º consumidor.
  def transcript(conversation)
    return nil if conversation.blank?

    messages = conversation.messages.where(message_type: [:incoming, :outgoing], private: false)
                           .order(:created_at).last(MAX_MESSAGES)
    lines = messages.filter_map do |m|
      text = m.content_for_llm
      next if text.blank? || text == '[Attachment]'

      "#{m.incoming? ? 'Cliente' : 'Atendimento'}: #{text}"
    end
    lines.presence && "Conversa (WhatsApp/chat):\n#{lines.join("\n")}"
  end

  def restore_name(lead, content)
    first = lead.name.to_s.split.first
    first.blank? ? content : content.gsub('[nome]', first)
  end
end
