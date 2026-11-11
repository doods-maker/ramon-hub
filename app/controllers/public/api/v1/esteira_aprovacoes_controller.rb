# Porta do hook da esteira (ADR 0014): abre o pedido de permissão e consulta a resposta. Quem decide é a tela do hub;
# este token só cria pedido e lê status. Header com hífen: o Caddy descarta header com sublinhado.
class Public::Api::V1::EsteiraAprovacoesController < PublicController
  before_action :verify_token

  def show
    aprovacao = RamonAprovacaoAgente.find(params[:id])
    render json: { status: aprovacao.status, motivo: aprovacao.entregar_motivo! }
  end

  def create
    entrada = params[:entrada]
    return head :unprocessable_entity unless entrada.nil? || entrada.is_a?(ActionController::Parameters)

    aprovacao = RamonAprovacaoAgente.abrir!(caso: params[:caso], ferramenta: params.require(:ferramenta),
                                            entrada: entrada&.to_unsafe_h || {})
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
