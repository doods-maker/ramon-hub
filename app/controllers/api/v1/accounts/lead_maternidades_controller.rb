# Salário-maternidade (fatia 2 do motor): RMI, carência (sempre 0) e duração
# (120 dias). Usa o CNIS anexado ao lead, igual ao elegibilidades. Cálculo
# efêmero — sem persistência.
class Api::V1::Accounts::LeadMaternidadesController < Api::V1::Accounts::BaseController
  before_action :fetch_lead
  include RegistraCalculo

  CATEGORIAS = %w[empregada ci_facultativa especial].freeze

  def create
    authorize(@lead, :show?)
    return render json: { error: 'data do evento inválida — use o formato AAAA-MM-DD' }, status: :unprocessable_entity if data_evento.blank?

    unless categoria_valida?
      return render json: { error: 'categoria inválida — use empregada, ci_facultativa ou especial' },
                    status: :unprocessable_entity
    end

    render json: Ramon::MotorClient.maternidade(motor_payload)
    registrar_calculo('maternidade')
  rescue Ramon::MotorClient::ValidationError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Ramon::MotorClient::UnavailableError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end

  def permitted
    params.permit(:data_evento, :categoria)
  end

  def data_evento
    @data_evento ||= data(permitted[:data_evento])
  end

  def data(valor)
    Date.iso8601(valor.to_s)
  rescue ArgumentError
    nil
  end

  def categoria_valida?
    CATEGORIAS.include?(permitted[:categoria])
  end

  def cnis_entrada
    @cnis_entrada ||= @lead.cnis&.dig('entrada') || {}
  end

  # Sem CNIS anexado, cai pro nascimento/sexo do contato — mesmo fallback do
  # elegibilidades.
  def segurado
    cnis_entrada['segurado'].presence ||
      { nascimento: @lead.contact&.data_nascimento&.iso8601, sexo: @lead.contact&.sexo.presence || 'M' }
  end

  def motor_payload
    {
      segurado: segurado,
      data_evento: data_evento.iso8601,
      competencias: cnis_entrada['competencias'] || [],
      vinculos: cnis_entrada['vinculos'] || [],
      categoria: permitted[:categoria]
    }
  end
end
