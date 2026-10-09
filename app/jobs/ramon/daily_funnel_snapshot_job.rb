class Ramon::DailyFunnelSnapshotJob < ApplicationJob
  queue_as :scheduled_jobs

  # Regra fixa (decisão do Eduardo 08/10): todas as contas, todo dia às 00:05 (config/schedule.yml).
  def perform
    Account.find_each do |account|
      Ramon::FunnelSnapshotService.new(account: account).perform
    end
  end
end
