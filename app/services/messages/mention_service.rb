class Messages::MentionService
  pattr_initialize [:message!]

  def perform
    return unless valid_mention_message?(message)

    validated_mentioned_ids = filter_mentioned_ids_by_inbox
    return if validated_mentioned_ids.blank?

    # FORK(ramon): na Equipe o @ só avisa (não vira participante, não entra em "Menções")
    unless equipe?
      Conversations::UserMentionJob.perform_later(validated_mentioned_ids, message.conversation.id, message.account.id)
      add_mentioned_users_as_participants(validated_mentioned_ids)
    end
    generate_notifications_for_mentions(validated_mentioned_ids)
  end

  private

  def equipe?
    message.inbox.equipe?
  end

  def valid_mention_message?(message)
    (message.private? || equipe?) && message.content.present? && mentioned_ids.present?
  end

  def mentioned_ids
    user_mentions = message.content.scan(%r{\(mention://user/(\d+)/(.+?)\)}).map(&:first)
    team_mentions = message.content.scan(%r{\(mention://team/(\d+)/(.+?)\)}).map(&:first)

    expanded_user_ids = expand_team_mentions_to_users(team_mentions)

    (user_mentions + expanded_user_ids + todos_ids).uniq
  end

  # FORK(ramon): @todos só vale no canal de grupo da Equipe (o autor é pulado em self_mention?)
  def todos_ids
    return [] unless equipe? && message.content.include?('(mention://todos/0/todos)') && Ramon::Equipe.tipo(message.conversation) == 'grupo'

    participant_ids.map(&:to_s)
  end

  def participant_ids
    message.conversation.conversation_participants.pluck(:user_id)
  end

  def expand_team_mentions_to_users(team_ids)
    return [] if team_ids.blank?

    message.inbox.account.teams
           .joins(:team_members)
           .where(id: team_ids)
           .pluck('team_members.user_id')
           .map(&:to_s)
  end

  def valid_mentionable_user_ids
    @valid_mentionable_user_ids ||= equipe? ? participant_ids : native_mentionable_user_ids
  end

  def native_mentionable_user_ids
    inbox = message.inbox
    inbox.account.administrators.pluck(:id) + inbox.members.pluck(:id)
  end

  def filter_mentioned_ids_by_inbox
    mentioned_ids & valid_mentionable_user_ids.map(&:to_s)
  end

  def generate_notifications_for_mentions(validated_mentioned_ids)
    validated_mentioned_ids.each do |user_id|
      next if self_mention?(user_id)

      NotificationBuilder.new(
        notification_type: 'conversation_mention',
        user: User.find(user_id),
        account: message.account,
        primary_actor: message.conversation,
        secondary_actor: message
      ).perform
    end
  end

  def self_mention?(user_id)
    message.sender_type == 'User' && user_id.to_i == message.sender_id
  end

  def add_mentioned_users_as_participants(validated_mentioned_ids)
    validated_mentioned_ids.each do |user_id|
      message.conversation.conversation_participants.find_or_create_by(user_id: user_id)
    end
  end
end
