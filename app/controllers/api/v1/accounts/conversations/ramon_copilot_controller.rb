class Api::V1::Accounts::Conversations::RamonCopilotController < Api::V1::Accounts::Conversations::BaseController
  def create
    mode = params[:mode].to_s
    return render_could_not_create_error('Modo inválido') unless Ramon::ConversationCopilotService::MODES.include?(mode)

    content = Ramon::ConversationCopilotService.new(@conversation, mode).perform
    render json: { content: content }
  rescue Ramon::ConversationCopilotService::EmptyConversationError,
         Ramon::LlmClient::MissingApiKeyError,
         Ramon::LlmClient::TransientError => e
    render_could_not_create_error(e.message)
  end
end
