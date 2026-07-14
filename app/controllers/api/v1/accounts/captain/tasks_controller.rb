class Api::V1::Accounts::Captain::TasksController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def rewrite
    result = Captain::RewriteService.new(
      account: Current.account,
      content: params[:content],
      operation: params[:operation],
      conversation_display_id: params[:conversation_display_id]
    ).perform

    render_result(result)
  end

  # Fork: resumo e sugestão de resposta saem pelo copiloto da banca
  # (Ramon::ConversationCopilotService — DeepSeek + pseudonimização LGPD),
  # não pelos serviços do Captain: a config "OpenAI" desta instalação aponta
  # pro Whisper local (só transcrição de áudio), então o caminho upstream
  # sempre devolvia "API server error".
  def summarize
    render_ramon_copilot('summary')
  end

  def reply_suggestion
    render_ramon_copilot('draft')
  end

  def label_suggestion
    result = Captain::LabelSuggestionService.new(
      account: Current.account,
      conversation_display_id: params[:conversation_display_id]
    ).perform

    render_result(result)
  end

  # Fork: "Perguntar ao AdvBox" — processos, andamentos e publicações do
  # cliente vindos da API do AdvBox + DeepSeek. O contexto volta no
  # follow_up_context para as perguntas seguintes (follow_up abaixo).
  def advbox
    render_advbox(pergunta: params[:message])
  end

  def follow_up
    ctx = params[:follow_up_context]&.to_unsafe_h
    if ctx.present? && ctx['advbox']
      return render_advbox(pergunta: params[:message], contexto: ctx['contexto'],
                           historico: ctx['historico'])
    end

    result = Captain::FollowUpService.new(
      account: Current.account,
      follow_up_context: ctx,
      user_message: params[:message],
      conversation_display_id: params[:conversation_display_id]
    ).perform

    render_result(result)
  end

  private

  # método (não constante congelada): em ambiente com reload as classes são
  # recriadas e um Array congelado no load guardaria as versões antigas —
  # o rescue nunca casaria (specs viravam 500)
  def erros_ramon
    [Ramon::ConversationCopilotService::EmptyConversationError,
     Ramon::AdvboxPerguntaService::SemClienteError,
     Ramon::AdvboxPerguntaService::SemProcessoError,
     Ramon::AdvboxClient::UnavailableError,
     Ramon::LlmClient::MissingApiKeyError,
     Ramon::LlmClient::TransientError]
  end

  def conversa
    Current.account.conversations.find_by(display_id: params[:conversation_display_id])
  end

  def render_ramon_copilot(mode)
    conversation = conversa
    return render json: { error: 'Conversa não encontrada' }, status: :unprocessable_content if conversation.nil?

    content = Ramon::ConversationCopilotService.new(conversation, mode).perform
    render json: { message: content }
  rescue *erros_ramon => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  def render_advbox(pergunta:, contexto: nil, historico: [])
    conversation = conversa
    return render json: { error: 'Conversa não encontrada' }, status: :unprocessable_content if conversation.nil?

    resultado = Ramon::AdvboxPerguntaService.new(
      conversation, pergunta: pergunta, contexto: contexto, historico: historico
    ).perform
    render json: { message: resultado[:message], follow_up_context: resultado[:follow_up_context] }
  rescue *erros_ramon => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  def render_result(result)
    if result.nil?
      render json: { message: nil }
    elsif result[:error]
      render json: { error: result[:error] }, status: :unprocessable_content
    else
      response_data = { message: result[:message] }
      response_data[:follow_up_context] = result[:follow_up_context] if result[:follow_up_context]
      render json: response_data
    end
  end

  def check_authorization
    authorize(:'captain/tasks')
  end
end

Api::V1::Accounts::Captain::TasksController.prepend_mod_with('Api::V1::Accounts::Captain::TasksController')
