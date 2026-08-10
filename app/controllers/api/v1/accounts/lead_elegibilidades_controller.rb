# Elegibilidade (qualidade de segurado, pendências de 1 clique, lacunas +
# simulação de preenchimento): usa o CNIS anexado ao lead (quando houver),
# igual ao painel. Cálculo efêmero — sem persistência.
class Api::V1::Accounts::LeadElegibilidadesController < Api::V1::Accounts::BaseController
  include CalculoProxy
  include RegistraCalculo

  def create
    authorize(@lead, :show?)
    return render json: { error: 'DER inválida — use o formato AAAA-MM-DD' }, status: :unprocessable_entity if der.blank?

    responder do
      render json: Ramon::MotorClient.elegibilidade(motor_payload)
      registrar_calculo('elegibilidade')
    end
  end

  private

  def permitted
    params.permit(:der, :data_referencia, :simular_lacunas, decisoes: [:desemprego, :facultativo])
  end

  def der
    @der ||= data(permitted[:der])
  end

  # decisoes chega como {desemprego, facultativo} com "true"/"false"/nil — só
  # repassa as chaves respondidas (nil = pergunta ainda em aberto).
  def decisoes
    return {} if permitted[:decisoes].blank?

    permitted[:decisoes].to_h.compact.symbolize_keys
  end

  def motor_payload
    payload = {
      segurado: segurado_do_cnis_ou_contato,
      der: der.iso8601,
      competencias: cnis_entrada['competencias'] || [],
      vinculos: cnis_entrada['vinculos'] || []
    }
    payload[:data_referencia] = permitted[:data_referencia] if permitted[:data_referencia].present?
    payload[:decisoes] = decisoes if decisoes.present?
    payload[:simular_lacunas] = true if ActiveModel::Type::Boolean.new.cast(permitted[:simular_lacunas])
    payload
  end
end
