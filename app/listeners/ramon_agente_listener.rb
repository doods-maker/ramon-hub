# frozen_string_literal: true

# Gatilho do agente do hub: nota privada começando com "@claude", escrita pelo Eduardo (Ramon::AgenteNotifyJob.chamado?).
# Webhook nativo não serve (Message#webhook_sendable? descarta private). B5-leads: a nota decide UMA vez entre o código
# (o job de sempre) e o fluxo migrado "Agente do hub" (gatilho Nota privada escrita), com reserva.
class RamonAgenteListener < BaseListener
  def message_created(event)
    message = event.data[:message]
    return unless Ramon::AgenteNotifyJob.chamado?(message)

    conversa = message.conversation
    dados = { 'caixa_id' => conversa.inbox_id, 'mensagem_id' => message.id, 'texto' => message.content.to_s.truncate(500) }
    Ramon::Fluxos::Migracao.decidir('agente', 'nota_escrita', conversa, dados) { Ramon::AgenteNotifyJob.perform_later(message.id) }
  end
end
