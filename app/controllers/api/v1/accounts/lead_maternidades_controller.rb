# Salário-maternidade (fatia 2 do motor): RMI, carência (sempre 0) e duração
# (120 dias). Usa o CNIS anexado ao lead, igual ao elegibilidades. Cálculo
# efêmero — sem persistência.
class Api::V1::Accounts::LeadMaternidadesController < Api::V1::Accounts::BaseController
  include CalculoProxy
  include RegistraCalculo

  CATEGORIAS = %w[empregada ci_facultativa especial].freeze

  def create
    authorize(@lead, :show?)
    return render json: { error: 'data do evento inválida — use o formato AAAA-MM-DD' }, status: :unprocessable_entity if data_evento.blank?

    unless categoria_valida?
      return render json: { error: 'categoria inválida — use empregada, ci_facultativa ou especial' },
                    status: :unprocessable_entity
    end

    responder do
      render json: Ramon::MotorClient.maternidade(motor_payload)
      registrar_calculo('maternidade')
    end
  end

  private

  def permitted
    params.permit(:data_evento, :categoria)
  end

  def data_evento
    @data_evento ||= data(permitted[:data_evento])
  end

  def categoria_valida?
    CATEGORIAS.include?(permitted[:categoria])
  end

  def motor_payload
    {
      segurado: segurado_do_cnis_ou_contato,
      data_evento: data_evento.iso8601,
      competencias: cnis_entrada['competencias'] || [],
      vinculos: cnis_entrada['vinculos'] || [],
      categoria: permitted[:categoria]
    }
  end
end
