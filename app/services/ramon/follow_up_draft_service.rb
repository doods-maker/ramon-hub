# Vigia de retomada (mapa comercial 23/07): pros leads parados do funil, gera
# rascunho de mensagem de retomada (LLM) + tarefa na Esteira, com contador em
# custom_attributes.follow_up. Nada é enviado ao cliente — nota nasce RASCUNHO
# e quem revisa e manda é o Eduardo.
class Ramon::FollowUpDraftService
  DAILY_CAP = 15
  MIN_GAP_DAYS = 5
  MAX_MESSAGES = 200
  PROVIDER = 'deepseek'.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você redige uma mensagem de retomada de WhatsApp para o atendente de um escritório de advocacia
    previdenciária enviar a um lead que parou de responder. Tom de "médico de confiança": caloroso,
    acolhedor, simples, sem juridiquês, sem pressão.
    Regras obrigatórias:
    - Curto, estilo WhatsApp: 2 a 4 frases.
    - NUNCA prometa resultado do caso nem prazo do INSS (regra da OAB).
    - Não invente fatos que não estejam na conversa.
    - Se precisar chamar o cliente pelo nome, escreva exatamente [nome].
    Responda APENAS com o texto da mensagem, sem aspas, sem comentários e sem assinatura.
  PROMPT

  def initialize(account:)
    @account = account
  end

  def perform
    eligible = Ramon::LeadRadar.stalled_leads(@account).select { |lead| eligible?(lead) }
    if eligible.size > DAILY_CAP
      Rails.logger.info("FollowUpDraftService: conta #{@account.id} estourou o teto diário (#{eligible.size} elegíveis, teto #{DAILY_CAP})")
    end
    batch = eligible.first(DAILY_CAP)
    batch.each { |lead| draft_for(lead) }
    summary_push(batch)
    batch.size
  end

  private

  def eligible?(lead)
    return false if lead.conversation_id.blank?
    return false if lead.lead_tasks.open_tasks.exists?(kind: 'follow_up')

    last_at = lead.custom_attributes.dig('follow_up', 'ultima_em')
    return true if last_at.blank?

    parsed = begin
      Time.zone.parse(last_at.to_s)
    rescue ArgumentError
      nil
    end
    # data venenosa (API grava qualquer coisa no jsonb) → trata como "nunca"
    parsed.nil? || parsed <= MIN_GAP_DAYS.days.ago
  end

  def draft_for(lead)
    attempt = lead.custom_attributes.dig('follow_up', 'tentativas').to_i + 1
    body = "RASCUNHO (revisar antes de enviar) — retomada nº #{attempt}:\n#{message_for(lead, attempt)}"
    # atômico: falha parcial deixaria nota órfã sem task/contador → retomada duplicada amanhã
    lead.transaction do
      lead.lead_notes.create!(account: @account, body: body.truncate(1000))
      lead.lead_tasks.create!(account: @account, kind: 'follow_up', title: "Retomada nº #{attempt}", due_at: Time.current.end_of_day)
      register_attempt(lead, attempt)
    end
    Ramon::EventoInline.registrar(lead.conversation,
                                  "⟳ Cadência do hub preparou o rascunho de retomada nº #{attempt} — revise e envie pelo painel.",
                                  tipo: 'cadencia_follow_up')
  end

  def message_for(lead, attempt)
    result = Ramon::LlmClient.complete(provider: PROVIDER,
                                       model: ENV.fetch('RAMON_COPILOT_MODEL', 'deepseek-chat'),
                                       system: SYSTEM_PROMPT, user: user_prompt(lead, attempt))
    restore_name(lead, result.content)
  rescue StandardError => e
    # falha de LLM não derruba o lote — cai no texto estático
    Rails.logger.warn("FollowUpDraftService: LLM falhou p/ lead #{lead.id} (#{e.class}: #{e.message}) — usando fallback")
    fallback_message(lead)
  end

  def fallback_message(lead)
    "Oi #{first_name(lead)}, tudo bem? Passando pra saber se você ainda tem interesse em olhar o seu caso com a gente. " \
      'Qualquer coisa, estou por aqui!'
  end

  # Pseudonimizado (LGPD, mesmo padrão do Copilot): o texto só sai daqui mascarado.
  def user_prompt(lead, attempt)
    header = ["Tentativa de retomada nº #{attempt} — ângulo: #{angle_for(attempt)}.",
              "Tese/benefício: #{lead.thesis&.name || lead.benefit_type&.name || 'não informado'}.",
              "Lead parado há #{days_stalled(lead)} dias sem avanço."].join("\n")
    text = [header, transcript(lead.conversation)].compact_blank.join("\n\n")
    Ramon::Pseudonymizer.mask(text, names: [lead.name, lead.contact&.name])
  end

  # O ângulo muda com a tentativa: repetir "oi, sumido" queima o lead.
  def angle_for(attempt)
    case attempt
    when 1 then 'lembrete leve e gentil de que estamos à disposição pra seguir com o caso'
    when 2 then 'agregue valor: traga UMA informação nova e útil sobre a tese/benefício em questão'
    else 'faça uma pergunta direta sobre o interesse em seguir e deixe a porta aberta pra quando a pessoa quiser'
    end
  end

  def days_stalled(lead)
    return 0 if lead.stage_entered_at.blank?

    (Time.zone.today - lead.stage_entered_at.to_date).to_i
  end

  # ponytail: espelha ConversationCopilotService#transcript; extrair helper comum se surgir um 4º consumidor.
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
    first = first_name(lead)
    first == 'cliente' ? content : content.gsub('[nome]', first)
  end

  def first_name(lead)
    lead.name.to_s.split.first.presence || 'cliente'
  end

  # lição lost update: reload antes do merge; escrever SÓ a chave follow_up.
  def register_attempt(lead, attempt)
    lead.reload
    follow_up = { 'tentativas' => attempt, 'ultima_em' => Time.current.iso8601 }
    lead.update!(custom_attributes: lead.custom_attributes.merge('follow_up' => follow_up))
  end

  # 1 push resumo por conta (não 1 por lead); o NtfyPushJob exige um lead — vai o último do lote.
  def summary_push(batch)
    return if batch.empty? || ENV.fetch('NTFY_TOPIC', nil).blank?

    Ramon::NtfyPushJob.perform_later(batch.last.id, title: 'Retomadas prontas pra revisar',
                                                    body: "#{batch.size} rascunho(s) de retomada esperando revisão no hub")
  end
end
