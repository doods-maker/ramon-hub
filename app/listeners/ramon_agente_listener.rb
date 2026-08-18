# frozen_string_literal: true

# Gatilho do agente do hub: nota privada começando com "@claude", escrita pelo
# Eduardo. Webhook nativo não serve (Message#webhook_sendable? descarta private).
class RamonAgenteListener < BaseListener
  def message_created(event)
    message = event.data[:message]
    return unless message.private? && message.content.to_s.lstrip.downcase.start_with?('@claude')
    return if ENV.fetch('RAMON_AGENTE_RUNNER_URL', nil).blank?
    return unless message.sender.is_a?(User) && message.sender.email.casecmp?(ENV.fetch('RAMON_AGENTE_EDUARDO_EMAIL', ''))

    Ramon::AgenteNotifyJob.perform_later(message.id)
  end
end
