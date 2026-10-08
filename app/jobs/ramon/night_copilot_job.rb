class Ramon::NightCopilotJob < ApplicationJob
  queue_as :scheduled_jobs

  # B5-conta: sem conta = o cron (as contas cujo fluxo "Copiloto noturno" não assumiu); com conta = o fluxo ou a reserva.
  def perform(account_id = nil)
    Ramon::Fluxos::Rotinas::Conta.cada_conta('copiloto_noturno', account_id) do |account|
      Ramon::NightCopilotService.new(account: account).perform
    rescue StandardError => e
      # uma conta com dado venenoso não pode abortar as demais nem virar retry-loop
      Rails.logger.error("NightCopilotJob: conta #{account.id} falhou (#{e.class}: #{e.message})")
    end
  end
end
