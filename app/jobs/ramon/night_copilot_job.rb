class Ramon::NightCopilotJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_each do |account|
      Ramon::NightCopilotService.new(account: account).perform
    rescue StandardError => e
      # uma conta com dado venenoso não pode abortar as demais nem virar retry-loop
      Rails.logger.error("NightCopilotJob: conta #{account.id} falhou (#{e.class}: #{e.message})")
    end
  end
end
