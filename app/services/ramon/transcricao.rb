# Transcrição da conversa (só mensagens públicas de cliente/atendimento) para prompts de LLM.
# Extraída do NightCopilotService; o texto sai cru — quem chama aplica o Pseudonymizer.
module Ramon::Transcricao
  # com_hora: cada linha leva "[dd/mm HH:MM] " (São Paulo) — o observador do funil compara com "Hoje" e com os desfazer.
  def self.de(conversation, limite: 200, com_hora: false)
    return nil if conversation.blank?

    messages = conversation.messages.where(message_type: [:incoming, :outgoing], private: false)
                           .order(:created_at).last(limite)
    lines = messages.filter_map do |m|
      text = m.content_for_llm
      next if text.blank? || text == '[Attachment]'

      linha(m, text, com_hora)
    end
    lines.presence && "Conversa (WhatsApp/chat):\n#{lines.join("\n")}"
  end

  def self.linha(message, text, com_hora)
    hora = "[#{message.created_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m %H:%M')}] " if com_hora
    "#{hora}#{message.incoming? ? 'Cliente' : 'Atendimento'}: #{text}"
  end
  private_class_method :linha
end
