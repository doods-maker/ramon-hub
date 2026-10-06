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
      content: params[:texto].to_s, sender: @account.agent_bots.find_by!(name: 'Claude')
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
      **params.permit(:pedido, :status, :resumo, :modelo, :esforco, :duracao_ms).to_h.symbolize_keys,
      lead_id: @account.leads.where(id: params[:lead_id]).pick(:id),
      conversation_id: conversation_pk(params[:conversation_id]), acoes: acoes, **uso_do_runner
    )
    render json: { id: exec.id }, status: :created
  end

  private

  # usage/total_cost_usd do `claude -p` (custo nominal da assinatura: a tela mostra "equivalente")
  def uso_do_runner
    params.permit(:input_tokens, :output_tokens, :custo_usd).to_h.symbolize_keys
  end

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
