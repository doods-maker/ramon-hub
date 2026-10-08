# Espelho noturno do Painel do Cliente. Falha de um cliente não derruba os outros.
class Ramon::PortalSyncJob < ApplicationJob
  queue_as :scheduled_jobs

  # B5-conta: sem conta = o cron (as contas cujo fluxo "Espelho do Painel" não assumiu, + o expurgo de acessos, que é da
  # instalação toda); com conta = o fluxo ou a reserva pediram aquela conta.
  def perform(account_id = nil)
    PortalAcesso.expurgar! if account_id.nil?
    Ramon::Fluxos::Rotinas::Conta.cada_conta('espelho_painel', account_id) { |account| espelhar(account) }
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
