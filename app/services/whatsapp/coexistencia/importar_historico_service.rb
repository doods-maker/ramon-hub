# Webhook `history` da coexistência: até 6 meses de conversas do app WhatsApp Business, em lotes por fase
# (0 = dia 0–1, 1 = dia 1–90, 2 = dia 90–180). Tudo entra em silêncio (Ramon::Silencio): uma conversa
# resolvida por contato, marcada `importado_coexistencia`, sem lead, IA, funil nem reenvio.
class Whatsapp::Coexistencia::ImportarHistoricoService
  HISTORICO_RECUSADO = 2_593_109
  MIDIAS = %w[media_placeholder image video audio document sticker].freeze

  def initialize(channel:, value:)
    @channel = channel
    @inbox = channel.inbox
    @value = value.with_indifferent_access
  end

  def perform
    return registrar_recusa if recusado?

    if @value[:history].blank?
      # ponytail: o conteúdo de mídia (value.messages[], só das 2 últimas semanas) fica para depois, se fizer falta.
      Rails.logger.info("[WHATSAPP] Coexistencia: webhook history sem history[] no canal #{@channel.id} (midia), ignorado")
      return
    end

    Ramon::Silencio.executar { @value[:history].each { |lote| importar_lote(lote) } }
  end

  private

  def recusado?
    @value.dig(:history, 0, :errors, 0, :code).to_i == HISTORICO_RECUSADO
  end

  def registrar_recusa
    Whatsapp::Coexistencia.registrar!(@channel, 'historico_recusado_em' => Time.current.iso8601)
    Ramon::NtfyPushJob.perform_later(
      title: 'Historico do WhatsApp nao foi compartilhado',
      body: 'No app do WhatsApp Business o histórico não foi liberado. Só os contatos entram no hub.'
    )
  end

  def importar_lote(lote)
    fase = lote.dig(:metadata, :phase)
    progresso = lote.dig(:metadata, :progress)
    Array(lote[:threads]).each { |thread| importar_thread(thread) }
    Rails.logger.info(
      "[WHATSAPP] Coexistencia: historico do canal #{@channel.id} fase #{fase} lote #{lote.dig(:metadata, :chunk_order)} progresso #{progresso}"
    )
    avisar_fim if fase.to_i == 2 && progresso.to_i == 100
  end

  def avisar_fim
    Ramon::NtfyPushJob.perform_later(
      title: 'Historico do WhatsApp importado',
      body: 'As conversas do app entraram no hub como resolvidas, sem IA, funil nem aviso ao time.'
    )
  end

  def importar_thread(thread)
    telefone = telefone_da(thread)
    # Webhook pode vir repetido, e mensagens depois do onboarding já chegaram por messages/smb_message_echoes:
    # filtra antes de criar qualquer coisa, para não nascer conversa importada vazia.
    novas = Array(thread[:messages]).reject { |mensagem| ja_importada?(mensagem) }
    return Rails.logger.info("[WHATSAPP] Coexistencia: thread sem telefone ou ja importada (canal #{@channel.id})") if telefone.blank? || novas.empty?

    contact_inbox = Whatsapp::Coexistencia.contact_inbox!(@inbox, telefone, thread.dig(:context, :username))
    # Fases, lotes e reentregas do mesmo contato podem rodar em paralelo no Sidekiq: a trava serializa o
    # find-or-create da conversa e as mensagens (importar_mensagem reconfere o wamid já com a trava).
    # O commit do with_lock (e os after_commit) cai dentro do Ramon::Silencio.executar de #perform.
    # ponytail: trava de linha por contact_inbox; se um contato tiver lotes enormes, trocar por fila por contato.
    contact_inbox.with_lock do
      conversa = conversa_importada(contact_inbox, ultima_atividade(novas))
      novas.each { |mensagem| importar_mensagem(conversa, contact_inbox.contact, mensagem) }
    end
  rescue ActiveRecord::RecordInvalid => e
    # Telefone que o Contact não aceita perde só esta thread, não o lote inteiro.
    Rails.logger.error("[WHATSAPP] Coexistencia: thread nao importada no canal #{@channel.id}: #{e.message}")
  end

  def telefone_da(thread)
    Whatsapp::Coexistencia.telefone(thread[:id]) || Whatsapp::Coexistencia.telefone(thread.dig(:context, :wa_id))
  end

  def ja_importada?(mensagem)
    mensagem[:id].blank? || Message.exists?(inbox_id: @inbox.id, source_id: mensagem[:id])
  end

  # Uma conversa importada por contato na caixa; lotes seguintes reaproveitam.
  def conversa_importada(contact_inbox, ultima)
    existente = @inbox.conversations.where(contact_id: contact_inbox.contact_id)
                      .find_by("conversations.additional_attributes ->> ? = 'true'", Whatsapp::Coexistencia::MARCA)
    return atualizar_atividade(existente, ultima) if existente

    conversa = Conversation.create!(account_id: @inbox.account_id, inbox_id: @inbox.id, contact_id: contact_inbox.contact_id,
                                    contact_inbox_id: contact_inbox.id, status: :resolved,
                                    additional_attributes: { Whatsapp::Coexistencia::MARCA => true })
    # before_create põe pending em caixa com bot e preenche waiting_since; a importada nasce resolvida e lida.
    # rubocop:disable Rails/SkipsModelValidations
    conversa.update_columns(status: :resolved, waiting_since: nil, agent_last_seen_at: Time.current, last_activity_at: ultima)
    # rubocop:enable Rails/SkipsModelValidations
    conversa
  end

  def atualizar_atividade(conversa, ultima)
    # rubocop:disable Rails/SkipsModelValidations
    conversa.update_columns(last_activity_at: ultima) if conversa.last_activity_at.blank? || ultima > conversa.last_activity_at
    # rubocop:enable Rails/SkipsModelValidations
    conversa
  end

  def ultima_atividade(mensagens)
    mensagens.map { |mensagem| momento(mensagem) }.max
  end

  def momento(mensagem)
    mensagem[:timestamp].present? ? Time.zone.at(mensagem[:timestamp].to_i) : Time.current
  end

  def importar_mensagem(conversa, contato, mensagem)
    return if ja_importada?(mensagem)

    conversa.messages.create!(
      account_id: @inbox.account_id, inbox_id: @inbox.id, source_id: mensagem[:id], content: conteudo(mensagem),
      created_at: momento(mensagem), **direcao(mensagem, contato)
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[WHATSAPP] Coexistencia: mensagem #{mensagem[:id]} nao importada no canal #{@channel.id}: #{e.message}")
  end

  # Do escritório quando `from` é o número do canal (eco do app, como smb_message_echoes); senão, do contato.
  def direcao(mensagem, contato)
    if mensagem[:from].to_s == numero_do_canal
      { message_type: :outgoing, status: :delivered, sender: nil,
        content_attributes: { Whatsapp::Coexistencia::MARCA => true, 'external_echo' => true } }
    else
      { message_type: :incoming, status: :sent, sender: contato, content_attributes: { Whatsapp::Coexistencia::MARCA => true } }
    end
  end

  def conteudo(mensagem)
    tipo = mensagem[:type].to_s
    return mensagem.dig(:text, :body) if tipo == 'text'
    return I18n.t('conversations.messages.whatsapp.historico_midia') if MIDIAS.include?(tipo)

    I18n.t('conversations.messages.whatsapp.historico_nao_importado', tipo: tipo.presence || 'mensagem')
  end

  def numero_do_canal
    @numero_do_canal ||= @channel.phone_number.delete('+')
  end
end
