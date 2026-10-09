# frozen_string_literal: true

# Gatilho do agente do hub (regra fixa, decisão do Eduardo 08/10): nota privada começando com "@claude", escrita pelo
# Eduardo (Ramon::AgenteNotifyJob.chamado?). Webhook nativo não serve (Message#webhook_sendable? descarta private).
class RamonAgenteListener < BaseListener
  def message_created(event)
    message = event.data[:message]
    Ramon::AgenteNotifyJob.perform_later(message.id) if Ramon::AgenteNotifyJob.chamado?(message)
  end
end
