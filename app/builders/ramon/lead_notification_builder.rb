class Ramon::LeadNotificationBuilder
  # Builder próprio (não usar o NotificationBuilder core): as guardas de
  # contact.blocked?/conversation de lá assumem primary_actor Conversation.
  # notification_type/meta opcionais: reunião marcada/lembrete/cancelada reusam
  # o mesmo sino (primary_actor = Lead) com o texto vindo do meta.
  pattr_initialize [:lead!, :notification_type, :meta]

  def perform
    # SELECT DISTINCT users.* quebra no Postgres (users.tokens é json, sem
    # operador de igualdade) — deduplicar pelos ids, não pelas linhas.
    user_ids = lead.account.account_users.pluck(:user_id).uniq
    User.where(id: user_ids).find_each do |user|
      user.notifications.create!(
        notification_type: notification_type || 'ramon_lead_created',
        account: lead.account,
        primary_actor: lead,
        meta: meta || {}
      )
    end

    return if notification_type.present? # push do ntfy só no lead novo (reunião tem o seu no MeetingReminderJob)

    Ramon::NtfyPushJob.perform_later(lead.id) if ENV.fetch('NTFY_TOPIC', nil).present?
  end
end
