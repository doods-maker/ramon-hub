class Ramon::LeadNotificationBuilder
  # Builder próprio (não usar o NotificationBuilder core): as guardas de
  # contact.blocked?/conversation de lá assumem primary_actor Conversation.
  # notification_type/meta opcionais: reunião marcada/lembrete/cancelada reusam
  # o mesmo sino (primary_actor = Lead) com o texto vindo do meta.
  # user_ids opcional: só esses recebem (alerta de SLA vai pro SDR do lead); sem ele, quem vê o lead (LeadPolicy::Scope).
  pattr_initialize [:lead!, :notification_type, :meta, :user_ids]

  def perform
    ids = user_ids.presence || LeadPolicy.quem_ve(lead).map(&:id)
    User.where(id: ids).find_each do |user|
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
