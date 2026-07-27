# Tela Cálculos ← AdvBox (spec 2026-07-20-calculos-advbox-design): busca de
# cadastro no AdvBox sob demanda + criação do caso de cálculo oculto.
class Api::V1::Accounts::RamonCalculosController < Api::V1::Accounts::BaseController
  LIMIT = 15
  CAMPOS = %w[id name identification cellphone birthdate email].freeze

  before_action :current_account
  before_action :check_authorization

  # Proxy da busca de clientes do AdvBox — 1 chamada por clique (teto 500/dia lá).
  def advbox_customers
    render json: { payload: advbox_list.map { |c| CAMPOS.index_with { |campo| c[campo] } } }
  rescue Ramon::AdvboxClient::UnavailableError
    render json: { error: 'ADVBOX_UNAVAILABLE' }, status: :service_unavailable
  end

  # Cálculo sem cliente: a tela Cálculos abre a calculadora direto, sem pedir
  # nome antes (uso "hub = Previdenciarista"). Um caso de rascunho por usuário,
  # reaproveitado e SEMPRE limpo na entrada — CNIS de um cálculo anterior não
  # pode vazar pro seguinte (viraria RMI da pessoa errada). Nasce sem contato e
  # com source calculo-advbox: invisível no funil (ver Lead.funil).
  def rascunho
    lead = Current.account.leads.find_or_create_by!(
      source: Lead::FONTE_CALCULO, contact_id: nil, name: "Cálculo rápido — #{Current.user.name}"
    ) { |novo| novo.lead_stage = Current.account.lead_stages.order(:position).first }
    lead.update!(cnis: nil)
    render json: lead.push_event_data.merge(cnis_resumo: lead.cnis_resumo)
  end

  def criar_caso
    result = Ramon::CalculoCasoService.new(account: Current.account, params: caso_params).perform
    render json: {
      contact: result[:contact].slice(:id, :name),
      leads: result[:leads].map(&:push_event_data)
    }
  end

  private

  # Termo com cara de CPF (11 dígitos) vira busca por identification.
  def advbox_list
    q = params[:q].to_s.strip
    return [] if q.length < 2 # não queima quota (500/dia) com busca vazia

    digits = q.gsub(/\D/, '')
    filtro = digits.length == 11 ? { identification: digits } : { name: q }
    resposta = Ramon::AdvboxClient.customers(filtro.merge(limit: LIMIT))
    resposta.is_a?(Hash) ? Array(resposta['data']) : Array(resposta)
  end

  def caso_params
    params.permit(:contact_id, :nome, :cpf, :telefone, :nascimento, :email)
  end

  def check_authorization
    authorize(:ramon_calculos, :"#{action_name}?")
  end
end
