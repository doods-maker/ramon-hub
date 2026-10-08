class Ramon::DailyFunnelSnapshotJob < ApplicationJob
  queue_as :scheduled_jobs

  # B5-conta: sem conta = o cron (as contas cujo fluxo "Retrato do funil" não assumiu); com conta = o fluxo ou a reserva.
  def perform(account_id = nil)
    Ramon::Fluxos::Rotinas::Conta.cada_conta('retrato_funil', account_id) do |account|
      Ramon::FunnelSnapshotService.new(account: account).perform
    end
  end
end
