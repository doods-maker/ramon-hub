class Conversations::ActivityMessageJob < ApplicationJob
  queue_as :high

  # ramon: com apos_id (aviso de handoff por cota, agendado), não sai se uma pessoa respondeu depois daquela mensagem
  def perform(conversation, message_params, apos_id = nil)
    return if apos_id && conversation.messages.outgoing.where(sender_type: 'User', private: false).exists?(['id > ?', apos_id])

    conversation.messages.create!(message_params)
  end
end
