# Resumo diário das 8h (mock 3f): push ntfy pro SDR + e-mail digest pra
# gestão. Cada canal é opt-in por env (NTFY_TOPIC / SMTP_ADDRESS) — sem
# config, NO-OP silencioso.
class Ramon::DailyDigestJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_each do |account|
      deliver(account)
    rescue StandardError => e
      # uma conta com dado venenoso não pode abortar as demais nem virar retry-loop
      Rails.logger.error("DailyDigestJob: conta #{account.id} falhou (#{e.class}: #{e.message})")
    end
  end

  private

  def deliver(account)
    digest = Ramon::DailyDigestService.new(account: account)
    send_push(digest)
    send_email(account, digest)
  end

  def send_push(digest)
    return if ENV.fetch('NTFY_TOPIC', nil).blank?

    body = digest.push_body
    return if body.blank? # dia zerado = não acorda ninguém

    Ramon::NtfyPushJob.perform_later(title: 'Ramon Hub · seu dia', body: body)
  end

  def send_email(account, digest)
    return if ENV.fetch('SMTP_ADDRESS', nil).blank?

    AdministratorNotifications::RamonDigestMailer.with(account: account).daily_digest(digest).deliver_now
  end
end
