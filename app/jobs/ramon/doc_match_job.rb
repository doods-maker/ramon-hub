# Roda o Ramon::DocMatchService pra 1 mensagem incoming com anexo — disparado
# pelo RamonLeadListener#message_created assim que o lead tem checklist pendente.
class Ramon::DocMatchJob < ApplicationJob
  queue_as :low
  retry_on Ramon::LlmClient::TransientError, wait: :polynomially_longer, attempts: 3
  retry_on ActiveStorage::FileNotFoundError, wait: 5.seconds, attempts: 3

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message.blank?

    Ramon::DocMatchService.new(message).perform
  end
end
