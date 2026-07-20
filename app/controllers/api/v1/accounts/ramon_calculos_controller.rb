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
