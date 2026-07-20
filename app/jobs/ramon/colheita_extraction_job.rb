# Extrai a colheita da conversa. Dois disparos: (1) quando o Whisper termina de
# transcrever um áudio (enterprise Messages::AudioTranscriptionService), por
# message_id; (2) sob demanda pelo botão do painel do lead (RamonColheita
# controller), por lead_id. NÃO roda mais automático a cada mensagem de chat
# (decisão do Eduardo 20/07: colheita só sob demanda — evita re-extração O(n²)).
class Ramon::ColheitaExtractionJob < ApplicationJob
  queue_as :low
  retry_on Ramon::LlmClient::TransientError, wait: :polynomially_longer, attempts: 3

  def perform(message_id = nil, lead_id: nil)
    lead = lead_from(message_id, lead_id)
    return if lead.blank?

    Ramon::ColheitaExtractionService.new(lead).perform
  end

  private

  def lead_from(message_id, lead_id)
    return Lead.find_by(id: lead_id) if lead_id.present?

    message = Message.find_by(id: message_id)
    return if message&.conversation_id.blank?

    Lead.find_by(conversation_id: message.conversation_id)
  end
end
