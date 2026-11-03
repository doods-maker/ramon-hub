# Porta do hook da esteira (ADR 0014): abre o pedido de permissão e consulta a resposta. Quem decide é a tela do hub;
# este token só cria pedido e lê status. Header com hífen: o Caddy descarta header com sublinhado.
class Public::Api::V1::EsteiraAprovacoesController < PublicController
  before_action :verify_token

  def show
    render json: { status: RamonAprovacaoAgente.find(params[:id]).status }
  end

  def create
    aprovacao = RamonAprovacaoAgente.abrir!(caso: params[:caso].to_s.truncate(80), ferramenta: params.require(:ferramenta).to_s.truncate(200),
                                            entrada: params[:entrada]&.to_unsafe_h || {})
    # O ntfy é público: o push não leva caso, ferramenta nem dado de cliente.
    Ramon::NtfyPushJob.perform_later(title: 'Esteira pede aprovacao', body: 'Abra Agentes no hub para responder.')
    render json: { id: aprovacao.id }, status: :created
  end

  private

  def verify_token
    esperado = ENV.fetch('RAMON_ESTEIRA_APROVACOES_TOKEN', '')
    recebido = request.headers['X-Esteira-Token'].to_s
    head :unauthorized unless esperado.present? && ActiveSupport::SecurityUtils.secure_compare(recebido, esperado)
  end
end
