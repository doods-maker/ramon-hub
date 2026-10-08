# Avisa o runner do agente (Claude Code na VPS) que chegou uma nota @claude.
# Falha de rede não pode derrubar a criação da nota: loga e desiste.
class Ramon::AgenteNotifyJob < ApplicationJob
  queue_as :default

  # Quem chama o agente — a trava de sempre, num lugar só (RamonAgenteListener e a rotina agente_hub; a tela não a edita):
  # nota privada começando com "@claude", escrita pelo Eduardo (RAMON_AGENTE_EDUARDO_EMAIL), com o runner configurado.
  def self.chamado?(message)
    message.private? && message.content.to_s.lstrip.downcase.start_with?('@claude') &&
      ENV.fetch('RAMON_AGENTE_RUNNER_URL', nil).present? &&
      message.sender.is_a?(User) && message.sender.email.casecmp?(ENV.fetch('RAMON_AGENTE_EDUARDO_EMAIL', ''))
  end

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
