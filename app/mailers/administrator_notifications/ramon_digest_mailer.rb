# E-mail digest diário do funil (mock 3f) — tema light da marca, template
# ERB próprio (sem o layout liquid padrão do Chatwoot).
class AdministratorNotifications::RamonDigestMailer < AdministratorNotifications::BaseMailer
  def daily_digest(digest)
    return unless smtp_config_set_or_development?

    recipients = admin_emails
    return if recipients.blank?

    @stats = digest.yesterday_stats
    @attention = digest.push_body
    @frontend_url = ENV.fetch('FRONTEND_URL', nil)
    @account_id = Current.account.id
    @command_center_url = "#{@frontend_url}/app/accounts/#{@account_id}/ramon"
    @funil_url = "#{@command_center_url}/funil"

    mail(to: recipients, subject: "Ramon Hub — resumo de ontem · #{@stats[:date_label]}") do |format|
      format.html { render layout: false }
    end
  end
end
