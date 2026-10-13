module Enterprise::MessageTemplates::HookExecutionService
  RESPOSTA_IA_ATRASO = 30..180 # segundos, sorteado a cada resposta no piloto
  ATRASO_ANEXO = 5.seconds # tempo pro anexo terminar de subir antes da IA ler

  def trigger_templates
    super
    return unless should_process_captain_response?
    return perform_handoff unless inbox.captain_active?

    schedule_captain_response
  end

  def should_send_greeting?
    return false if captain_handling_conversation?

    super
  end

  def should_send_out_of_office_message?
    return false if captain_handling_conversation?

    super
  end

  def should_send_email_collect?
    return false if captain_handling_conversation?

    super
  end

  private

  # ramon: no piloto (IA envia sozinha) a resposta sai com atraso aleatório (30s–3min) pra
  # não ter ritmo de robô. Rascunho/manual: sem espera (quem envia é a pessoa). O id da
  # mensagem vai junto: se o cliente mandar outra antes, só o job da mais nova responde.
  def schedule_captain_response
    job = Captain::Conversation::ResponseBuilderJob.set(wait: atraso_resposta_ia)
    job.perform_later(conversation, conversation.inbox.captain_assistant, message.id)
  end

  # ponytail: o modo é lido no agendamento; trocar de modo durante a espera não muda o atraso
  def atraso_resposta_ia
    return rand(RESPOSTA_IA_ATRASO).seconds if Ramon::CopilotoModo.piloto?(Ramon::CopilotoModo.of(conversation))

    message.attachments.present? ? ATRASO_ANEXO : 0
  end

  def should_process_captain_response?
    conversation.pending? && message.incoming? && inbox.captain_assistant.present?
  end

  def perform_handoff
    return unless conversation.pending?

    Rails.logger.info("Captain limit exceeded, performing handoff mid-conversation for conversation: #{conversation.id}")
    agendar_aviso_de_handoff if Ramon::CopilotoModo.piloto?(Ramon::CopilotoModo.of(conversation))
    conversation.bot_handoff!
    send_out_of_office_message_after_handoff
  end

  # ramon: limite de respostas da IA estourado → mesmo texto do handoff normal (config do assistente,
  # senão i18n na língua da conta) e mesmo atraso do piloto. Fora do piloto nada vai pro cliente.
  # ponytail: o aviso sai mesmo se um humano responder durante a espera — caso raro (limite de 100 mil)
  def agendar_aviso_de_handoff
    content = inbox.captain_assistant.config['handoff_message'].presence ||
              I18n.with_locale(conversation.account.locale) { I18n.t('conversations.captain.handoff') }
    params = { message_type: :outgoing, account_id: conversation.account_id, inbox_id: conversation.inbox_id, content: content }
    Conversations::ActivityMessageJob.set(wait: atraso_resposta_ia).perform_later(conversation, params)
  end

  def send_out_of_office_message_after_handoff
    # Campaign conversations should never receive OOO templates — the campaign itself
    # serves as the initial outreach, and OOO would be confusing in that context.
    return if conversation.campaign.present?

    ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(conversation)
  end

  def captain_handling_conversation?
    conversation.pending? && inbox.respond_to?(:captain_assistant) && inbox.captain_assistant.present?
  end
end
