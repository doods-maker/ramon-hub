class Ramon::LeadNotificationBuilder
  # Builder próprio (não usar o NotificationBuilder core): as guardas de
  # contact.blocked?/conversation de lá assumem primary_actor Conversation.
  pattr_initialize [:lead!]

  def perform
    lead.account.users.distinct.find_each do |user|
      user.notifications.create!(
        notification_type: 'ramon_lead_created',
        account: lead.account,
        primary_actor: lead
      )
    end
  end
end
