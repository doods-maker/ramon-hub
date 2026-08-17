# API do agente do hub (Claude Code na VPS, usuário `agente`). Token na query
# (mesmo padrão do MCP: filter_parameters mascara). Só leitura de contexto +
# escritas determinísticas que o runner faz DEPOIS do LLM: nota privada,
# arquivo no Drive, linha de trilha. Spec: docs/superpowers/specs/2026-08-17-agente-hub-design.md
class Public::Api::V1::AgenteController < PublicController
  before_action :verify_token
  before_action :fetch_account

  def contexto
    render json: Ramon::AgenteContextoService.new(fetch_conversation).perform
  end

  def nota
    conversation = fetch_conversation
    message = conversation.messages.create!(
      account: @account, inbox: conversation.inbox, message_type: :outgoing, private: true,
      content: params[:texto].to_s, sender: @account.agent_bots.find_by(name: 'Claude')
    )
    render json: { id: message.id }, status: :created
  end

  def arquivo
    lead = @account.leads.find(params[:lead_id])
    return render json: { error: 'Drive não configurado' }, status: :service_unavailable unless Ramon::DriveClient.configured?

    pasta = Ramon::DriveExportService.new(lead).pasta_cliente_id
    file_id = Ramon::DriveClient.upload(name: params[:nome].to_s, io: StringIO.new(params[:conteudo].to_s),
                                        content_type: params[:content_type].presence || 'text/markdown', parent_id: pasta)
    render json: { file_id: file_id, url: "https://drive.google.com/file/d/#{file_id}/view" }, status: :created
  end

  def execucoes
    exec = @account.agente_execucoes.create!(
      pedido: params[:pedido], status: params[:status], resumo: params[:resumo], modelo: params[:modelo],
      esforco: params[:esforco], duracao_ms: params[:duracao_ms], lead_id: params[:lead_id],
      conversation_id: conversation_pk(params[:conversation_id]), acoes: acoes
    )
    render json: { id: exec.id }, status: :created
  end

  private

  # Payload livre vindo do runner (já autenticado pelo token) — vai cru pro jsonb.
  def acoes
    Array(params[:acoes]).map { |a| a.respond_to?(:to_unsafe_h) ? a.to_unsafe_h : a }
  end

  def fetch_conversation
    @account.conversations.find_by!(display_id: params[:conversation_id])
  end

  def conversation_pk(display_id)
    display_id.present? ? @account.conversations.find_by(display_id: display_id)&.id : nil
  end

  def fetch_account
    @account = Account.find(params[:account_id])
  end

  def verify_token
    secret = ENV.fetch('RAMON_AGENTE_TOKEN', nil)
    provided = params[:token].to_s
    return if secret.present? && provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, secret)

    head :unauthorized
  end
end
