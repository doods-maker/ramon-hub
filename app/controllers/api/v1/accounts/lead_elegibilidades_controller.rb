# Elegibilidade (qualidade de segurado, pendências de 1 clique, lacunas +
# simulação de preenchimento): usa o CNIS anexado ao lead (quando houver),
# igual ao painel. Cálculo efêmero — sem persistência.
class Api::V1::Accounts::LeadElegibilidadesController < Api::V1::Accounts::BaseController
  before_action :fetch_lead

  def create
    authorize(@lead, :show?)
    return render json: { error: 'DER inválida — use o formato AAAA-MM-DD' }, status: :unprocessable_entity if der.blank?

    render json: Ramon::MotorClient.elegibilidade(motor_payload)
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
    params.permit(:der, :data_referencia, :simular_lacunas, decisoes: [:desemprego, :facultativo])
  end

  def der
    @der ||= data(permitted[:der])
  end

  def data(valor)
    Date.iso8601(valor.to_s)
  rescue ArgumentError
    nil
  end

  def cnis_entrada
    @cnis_entrada ||= @lead.cnis&.dig('entrada') || {}
  end

  # Sem CNIS anexado, cai pro nascimento/sexo do contato (o front só libera
  # esta aba com canElegibilidade = der && cnis — CNIS é obrigatório; este
  # fallback é defesa de fronteira, não caminho esperado).
  def segurado
    cnis_entrada['segurado'].presence ||
      { nascimento: @lead.contact&.data_nascimento&.iso8601, sexo: @lead.contact&.sexo.presence || 'M' }
  end

  # decisoes chega como {desemprego, facultativo} com "true"/"false"/nil — só
  # repassa as chaves respondidas (nil = pergunta ainda em aberto).
  def decisoes
    return {} if permitted[:decisoes].blank?

    permitted[:decisoes].to_h.compact.symbolize_keys
  end

  def motor_payload
    payload = {
      segurado: segurado,
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
