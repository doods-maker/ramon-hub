class Ramon::DailyFollowUpJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_each do |account|
      next if Ramon::Fluxos::Retomada.assumiu?(account) # B4.3: o fluxo "Cadência de retomada" faz (Ramon::Fluxos::Relogio)

      # B4.3: o lote do dia sai pelo código → o dia do fluxo da cadência é reivindicado ANTES do lote (1–3 min): religar o
      # fluxo durante o lote, ou depois das 11h, não roda um 2º lote em paralelo/no mesmo dia.
      fluxo = Ramon::Fluxos::Retomada.fluxo(account)
      Ramon::Fluxos::Relogio.reivindicar_dia(fluxo, Time.find_zone!(Fluxo::ZONA).now) if fluxo
      Ramon::FollowUpDraftService.new(account: account).perform
    rescue StandardError => e
      # uma conta com dado venenoso não pode abortar as demais nem virar retry-loop
      Rails.logger.error("DailyFollowUpJob: conta #{account.id} falhou (#{e.class}: #{e.message})")
    end
  end
end
