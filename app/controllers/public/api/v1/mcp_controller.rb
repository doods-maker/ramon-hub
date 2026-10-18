# Endpoint MCP (custom connector dos projetos Claude Cowork) — consulta e
# escrita na API do AdvBox via Ramon::AdvboxMcpService. O claude.ai não
# envia header customizado em connector sem OAuth, então a auth é um token
# longo no path (mesmo padrão do ramon_leads/:capture_token) + rate-limit no
# rack_attack. Transporte streamable HTTP sem SSE: GET responde 405.
class Public::Api::V1::McpController < PublicController
  before_action :verify_token

  def create
    payload = JSON.parse(request.raw_post)
    # Cada tools/call é uma chamada HTTP serial ao AdvBox — batch sem teto seguraria um worker por minutos.
    return render_rpc_error(-32_600, 'Batch grande demais (máximo 20)', :bad_request) if payload.is_a?(Array) && payload.size > 20

    body = payload.is_a?(Array) ? payload.filter_map { |m| Ramon::AdvboxMcpService.handle(m) } : Ramon::AdvboxMcpService.handle(payload)
    return head :accepted if body.blank? # notificação (ex.: notifications/initialized) não tem resposta

    render json: body
  rescue JSON::ParserError
    render_rpc_error(-32_700, 'JSON inválido', :bad_request)
  rescue StandardError => e
    # Backstop: sem ele, exceção que escape do service vira 500 cru do Rails
    # (não-JSON-RPC) e quebra a conversa do cliente MCP de forma opaca.
    Rails.logger.error("AdvboxMcp erro interno: #{e.class}: #{e.message}")
    render_rpc_error(-32_603, 'Erro interno', :internal_server_error)
  end

  def not_allowed
    head :method_not_allowed
  end

  private

  def render_rpc_error(code, message, status)
    render json: { jsonrpc: '2.0', id: nil, error: { code: code, message: message } }, status: status
  end

  def verify_token
    secret = ENV.fetch('RAMON_MCP_TOKEN', nil)
    return head :unauthorized if secret.blank?

    provided = params[:token].to_s
    return if provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, secret)

    head :unauthorized
  end
end
