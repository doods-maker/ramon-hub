# Equipe · chat interno (ADR 0011): não-lidas da pessoa na caixa Equipe (badge do menu) e a conversa 1:1 sob demanda.
# Qualquer usuário da conta pode abrir 1:1 com outro; a conversa em si segue a ConversationPolicy.
class Api::V1::Accounts::RamonEquipeController < Api::V1::Accounts::BaseController
  def show
    render json: { inbox_id: Ramon::Equipe.caixa(Current.account)&.id,
                   nao_lidas: Ramon::Equipe.total_nao_lidas(Current.account, Current.user) }
  end

  def conversa
    return head :not_found unless Ramon::Equipe.caixa(Current.account)

    outro = Current.account.users.where.not(id: Current.user.id).find(params.require(:user_id))
    render json: { id: Ramon::Equipe.conversa_1a1(Current.account, Current.user, outro).display_id }
  end

  # Quem participa da conversa e até quando leu (segundos) — base do "visto" azul. Só para quem pode ver a conversa.
  def participantes
    conversation = Current.account.conversations.find_by!(display_id: params.require(:conversation_id))
    authorize conversation, :show?
    return head :not_found unless conversation.inbox.equipe?

    render json: conversation.conversation_participants.includes(:user).order(:user_id).map { |p| participante_json(p) }
  end

  private

  def participante_json(participante)
    { id: participante.user_id, name: participante.user.available_name, thumbnail: participante.user.avatar_url,
      last_seen_at: participante.last_seen_at&.to_i }
  end
end
