# Endpoint MCP (custom connector dos projetos Claude Cowork) — consulta
# somente-leitura à API do AdvBox via Ramon::AdvboxMcpService. O claude.ai não
# envia header customizado em connector sem OAuth, então a auth é um token
# longo no path (mesmo padrão do ramon_leads/:capture_token) + rate-limit no
# rack_attack. Transporte streamable HTTP sem SSE: GET responde 405.
class Public::Api::V1::McpController < PublicController
  before_action :verify_token

  def create
    payload = JSON.parse(request.raw_post)
    body = payload.is_a?(Array) ? payload.filter_map { |m| Ramon::AdvboxMcpService.handle(m) } : Ramon::AdvboxMcpService.handle(payload)
    return head :accepted if body.blank? # notificação (ex.: notifications/initialized) não tem resposta

    render json: body
  rescue JSON::ParserError
    render json: { jsonrpc: '2.0', id: nil, error: { code: -32_700, message: 'JSON inválido' } }, status: :bad_request
  end

  def not_allowed
    head :method_not_allowed
  end

  private

  def verify_token
    secret = ENV.fetch('RAMON_MCP_TOKEN', nil)
    return head :unauthorized if secret.blank?

    provided = params[:token].to_s
    return if provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, secret)

    head :unauthorized
  end
end
