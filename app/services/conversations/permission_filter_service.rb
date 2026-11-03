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
    # ramon: na caixa Equipe só quem participa; membro de caixa, atribuição e time não dão acesso (ADR 0011)
    comuns = conversations.where.not(inbox_id: caixa_equipe)
    comuns.where(inbox: user.inboxes.where(account_id: account.id))
          .or(comuns.where(assignee_id: user.id))
          .or(comuns.where(team_id: times_da_pessoa))
          .or(conversations.where(id: equipe_participations))
  end

  def times_da_pessoa
    user.teams.where(account_id: account.id).select(:id)
  end

  def caixa_equipe
    Inbox.where(account_id: account.id, equipe: true).select(:id)
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
