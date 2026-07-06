module Ramon
  class DailyFunnelSnapshotJob < ApplicationJob
    queue_as :scheduled_jobs

    def perform
      Account.find_each do |account|
        Ramon::FunnelSnapshotService.new(account: account).perform
      end
    end
  end
end
