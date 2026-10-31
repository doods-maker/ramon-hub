class Conversations::PermissionFilterService
  attr_reader :conversations, :user, :account

  def initialize(conversations, user, account)
    @conversations = conversations
    @user = user
    @account = account
  end

  def perform
    return conversations if user_role == 'administrator'

    accessible_conversations
  end

  private

  # ramon: além das caixas de que é membro, o agente vê o que foi atribuído a ele e a fila
  # dos times dele — é assim que a caixa do escritório separa o atendimento (ADR 0004)
  def accessible_conversations
    conversations.where(inbox: user.inboxes.where(account_id: account.id))
                 .or(conversations.where(assignee_id: user.id))
                 .or(conversations.where(team_id: user.teams.where(account_id: account.id).select(:id)))
                 .or(conversations.where(id: equipe_participations)) # ramon: caixa Equipe (ADR 0011)
  end

  def equipe_participations
    user.conversation_participants.joins(conversation: :inbox).where(inboxes: { equipe: true, account_id: account.id })
        .select(:conversation_id)
  end

  def account_user
    AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def user_role
    account_user&.role
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
