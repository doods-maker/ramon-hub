# Disparado quando o Whisper termina de transcrever um áudio da conversa
# (enterprise Messages::AudioTranscriptionService#update_transcription).
# ponytail: uma chamada de LLM por áudio transcrito (a última sobrescreve);
# debounce por conversa se o custo aparecer.
class Ramon::ColheitaExtractionJob < ApplicationJob
  queue_as :low
  retry_on Ramon::LlmClient::TransientError, wait: :polynomially_longer, attempts: 3

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message&.conversation_id.blank?

    lead = Lead.find_by(conversation_id: message.conversation_id)
    return if lead.blank?

    Ramon::ColheitaExtractionService.new(lead).perform
  end
end
