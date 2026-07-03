class Ramon::LeadNotificationBuilder
  # Builder próprio (não usar o NotificationBuilder core): as guardas de
  # contact.blocked?/conversation de lá assumem primary_actor Conversation.
  pattr_initialize [:lead!]

  def perform
    # SELECT DISTINCT users.* quebra no Postgres (users.tokens é json, sem
    # operador de igualdade) — deduplicar pelos ids, não pelas linhas.
    user_ids = lead.account.account_users.pluck(:user_id).uniq
    User.where(id: user_ids).find_each do |user|
      user.notifications.create!(
        notification_type: 'ramon_lead_created',
        account: lead.account,
        primary_actor: lead
      )
    end
  end
end
