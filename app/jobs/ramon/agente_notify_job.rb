# Avisa o runner do agente (Claude Code na VPS) que chegou uma nota @claude.
# Falha de rede não pode derrubar a criação da nota: loga e desiste.
class Ramon::AgenteNotifyJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message.blank?

    lead = message.account.leads.find_by(conversation_id: message.conversation_id)
    body = { account_id: message.account_id, conversation_id: message.conversation.display_id, message_id: message.id,
             lead_id: lead&.id, content: message.content.to_s, sender_email: message.sender.try(:email) }
    HTTParty.post(ENV.fetch('RAMON_AGENTE_RUNNER_URL'),
                  body: body.to_json, timeout: 5,
                  headers: { 'Content-Type' => 'application/json', 'X-Agente-Secret' => ENV.fetch('RAMON_AGENTE_SECRET', '') })
  rescue StandardError => e
    Rails.logger.warn("[Ramon::AgenteNotifyJob] runner indisponível: #{e.class}: #{e.message}")
  end
end
