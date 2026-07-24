# Pensão por morte (fatia 2 do motor): qualidade do falecido, quotas por
# dependente e decisões pendentes (união >=2 anos, desemprego). O CNIS
# anexado ao lead deve ser o DO FALECIDO (decisão de fluxo da fatia 2, front
# só avisa — o hub não valida de quem é o CNIS). Cálculo efêmero — sem
# persistência, igual ao elegibilidades/painel.
class Api::V1::Accounts::LeadPensoesController < Api::V1::Accounts::BaseController
  before_action :fetch_lead

  def create
    authorize(@lead, :show?)
    return render json: { error: 'data do óbito inválida — use o formato AAAA-MM-DD' }, status: :unprocessable_entity if data_obito.blank?
    return render json: { error: 'dependentes obrigatório — informe ao menos 1' }, status: :unprocessable_entity if dependentes.blank?

    render json: Ramon::MotorClient.pensao(motor_payload)
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
    params.permit(:data_obito, :valor_beneficio_obito,
                  dependentes: %i[tipo nascimento invalido inicio_uniao],
                  decisoes: %i[desemprego facultativo uniao_2_anos])
  end

  def data_obito
    @data_obito ||= data(permitted[:data_obito])
  end

  def data(valor)
    Date.iso8601(valor.to_s)
  rescue ArgumentError
    nil
  end

  # repassado cru pro motor — só a presença (min 1) é checada aqui, o
  # conteúdo (tipo/datas) é validado lá.
  def dependentes
    @dependentes ||= (permitted[:dependentes] || []).map(&:to_h)
  end

  def cnis_entrada
    @cnis_entrada ||= @lead.cnis&.dig('entrada') || {}
  end

  # Sem CNIS anexado, cai pro nascimento/sexo do contato — mesmo fallback do
  # elegibilidades (defesa de fronteira, o front gateia por CNIS presente).
  def segurado
    cnis_entrada['segurado'].presence ||
      { nascimento: @lead.contact&.data_nascimento&.iso8601, sexo: @lead.contact&.sexo.presence || 'M' }
  end

  # decisoes chega como {desemprego, facultativo, uniao_2_anos} com
  # true/false/nil — só repassa as chaves respondidas (false explícito
  # importa: é a resposta "Não" da pendência de 1 clique).
  def decisoes
    return {} if permitted[:decisoes].blank?

    permitted[:decisoes].to_h.compact.symbolize_keys
  end

  def motor_payload
    payload = {
      segurado: segurado,
      data_obito: data_obito.iso8601,
      competencias: cnis_entrada['competencias'] || [],
      vinculos: cnis_entrada['vinculos'] || [],
      dependentes: dependentes
    }
    payload[:valor_beneficio_obito] = permitted[:valor_beneficio_obito] if permitted[:valor_beneficio_obito].present?
    payload[:decisoes] = decisoes if decisoes.present?
    payload
  end
end
