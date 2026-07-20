# Disparado quando o Whisper termina de transcrever um áudio da conversa
# (enterprise Messages::AudioTranscriptionService#update_transcription) e,
# com debounce: true, alguns minutos depois de cada mensagem de chat do lead
# (RamonLeadListener) — na rajada, só o job da última mensagem roda de verdade.
class Ramon::ColheitaExtractionJob < ApplicationJob
  queue_as :low
  retry_on Ramon::LlmClient::TransientError, wait: :polynomially_longer, attempts: 3

  def perform(message_id, debounce: false)
    message = Message.find_by(id: message_id)
    return if message&.conversation_id.blank?

    lead = Lead.find_by(conversation_id: message.conversation_id)
    return if lead.blank?
    return if debounce && newer_incoming?(message)

    Ramon::ColheitaExtractionService.new(lead).perform
  end

  private

  def newer_incoming?(message)
    message.conversation.messages.where(message_type: :incoming).exists?(id: (message.id + 1)..)
  end
end
