class Api::V1::Accounts::Conversations::BaseController < Api::V1::Accounts::BaseController
  before_action :conversation

  private

  def conversation
    @conversation ||= Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize @conversation, :show?
    head :forbidden unless Ramon::Equipe.http_permitido?(@conversation, controller_path, action_name) # ramon: ADR 0011
  end
end
