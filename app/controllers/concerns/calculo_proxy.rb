# Comportamento comum dos proxies de cálculo (Simulador, Painel, Elegibilidade,
# Pensão, Maternidade, Planejamento, Liquidação e CNIS): resolver o lead da
# rota, parsear tipos e mapear os erros do motor pra HTTP. A regra de payload
# de cada tipo fica no controller do tipo — só o boilerplate mora aqui.
module CalculoProxy
  extend ActiveSupport::Concern

  included do
    before_action :fetch_lead
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end

  # O par de erros do motor, igual em todos os proxies: validação → 422,
  # motor fora → 503.
  def responder
    yield
  rescue Ramon::MotorClient::ValidationError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Ramon::MotorClient::UnavailableError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  def data(valor)
    Date.iso8601(valor.to_s)
  rescue ArgumentError
    nil
  end

  def decimal(valor)
    return if valor.blank?

    BigDecimal(valor.to_s)
  rescue ArgumentError
    nil
  end

  def cnis_entrada
    @cnis_entrada ||= @lead.cnis&.dig('entrada') || {}
  end

  # Sem CNIS anexado, cai pro nascimento/sexo do contato — defesa de fronteira:
  # o front gateia essas abas pela presença do CNIS.
  def segurado_do_cnis_ou_contato
    cnis_entrada['segurado'].presence ||
      { nascimento: @lead.contact&.data_nascimento&.iso8601, sexo: @lead.contact&.sexo.presence || 'M' }
  end
end
