class Ramon::CoachObjecaoJob < ApplicationJob
  queue_as :low
  retry_on Ramon::LlmClient::TransientError, wait: 30.seconds, attempts: 2

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message.blank?

    lead = message.account.leads.find_by(conversation_id: message.conversation_id)
    return if lead.blank? || lead.thesis_id.blank?

    Ramon::CoachObjecaoService.new(message, lead).perform
  end
end
