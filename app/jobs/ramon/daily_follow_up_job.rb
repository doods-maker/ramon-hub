class Ramon::DailyFollowUpJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_each do |account|
      Ramon::FollowUpDraftService.new(account: account).perform
    end
  end
end
