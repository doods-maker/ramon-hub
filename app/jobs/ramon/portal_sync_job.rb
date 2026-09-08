# Espelho noturno do Painel do Cliente. Falha de um cliente não derruba os outros.
class Ramon::PortalSyncJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    PortalCliente.where.not(convidado_em: nil).find_each do |cliente|
      Ramon::PortalSyncService.new(cliente).perform
    rescue Ramon::AdvboxClient::UnavailableError, Ramon::AdvboxClient::RequestError => e
      Rails.logger.warn("[Ramon::PortalSyncJob] cliente=#{cliente.id} #{e.class}: #{e.message}")
    end
  end
end
