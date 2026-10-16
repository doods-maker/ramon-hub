# Transcrição da conversa (só mensagens públicas de cliente/atendimento) para prompts de LLM.
# Extraída do NightCopilotService; o texto sai cru — quem chama aplica o Pseudonymizer.
module Ramon::Transcricao
  def self.de(conversation, limite: 200)
    return nil if conversation.blank?

    messages = conversation.messages.where(message_type: [:incoming, :outgoing], private: false)
                           .order(:created_at).last(limite)
    lines = messages.filter_map do |m|
      text = m.content_for_llm
      next if text.blank? || text == '[Attachment]'

      "#{m.incoming? ? 'Cliente' : 'Atendimento'}: #{text}"
    end
    lines.presence && "Conversa (WhatsApp/chat):\n#{lines.join("\n")}"
  end
end
