class Ramon::DailyFollowUpJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_each do |account|
      next if Ramon::Fluxos::Retomada.assumiu?(account) # B4.3: o fluxo "Cadência de retomada" faz (Ramon::Fluxos::Relogio)

      Ramon::FollowUpDraftService.new(account: account).perform
      # B4.3: o lote do dia saiu pelo código → o dia do fluxo da cadência fica reivindicado (ligá-lo de novo depois das
      # 11h não roda um 2º lote no mesmo dia).
      fluxo = Ramon::Fluxos::Retomada.fluxo(account)
      Ramon::Fluxos::Relogio.reivindicar_dia(fluxo, Time.find_zone!(Fluxo::ZONA).now) if fluxo
    rescue StandardError => e
      # uma conta com dado venenoso não pode abortar as demais nem virar retry-loop
      Rails.logger.error("DailyFollowUpJob: conta #{account.id} falhou (#{e.class}: #{e.message})")
    end
  end
end
