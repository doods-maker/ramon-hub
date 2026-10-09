# Espelho noturno do Painel do Cliente. Falha de um cliente não derruba os outros.
class Ramon::PortalSyncJob < ApplicationJob
  queue_as :scheduled_jobs

  # Regra fixa (decisão do Eduardo 08/10): o expurgo dos acessos (Marco Civil) e todas as contas, às 00:30.
  def perform
    PortalAcesso.expurgar!
    Account.find_each { |account| espelhar(account) }
  end

  private

  def espelhar(account)
    PortalCliente.where(account: account).where.not(convidado_em: nil).find_each do |cliente|
      Ramon::PortalSyncService.new(cliente).perform
    rescue Ramon::AdvboxClient::UnavailableError, Ramon::AdvboxClient::RequestError => e
      Rails.logger.warn("[Ramon::PortalSyncJob] cliente=#{cliente.id} #{e.class}: #{e.message}")
    end
  end
end
