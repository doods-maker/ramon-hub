# Contrato apto no painel do lead (Ramon::ContratoApto): o advogado da tese (ou o admin) valida ou devolve com motivo,
# o Closer reenvia depois de corrigir e o admin designa o advogado do lead. Quem vê o lead chega aqui; a regra de quem
# pode cada ação é do módulo (403 quando não pode, 422 quando o caso não está na situação certa).
class Api::V1::Accounts::LeadAptoController < Api::V1::Accounts::BaseController
  ACOES = %w[validar devolver reenviar designar].freeze

  before_action :fetch_lead

  def create
    authorize(@lead, :show?)
    return render json: { error: 'ACAO_INVALIDA' }, status: :unprocessable_entity unless ACOES.include?(params[:acao])

    executar # create.json.jbuilder devolve o lead (partial pelo caminho cheio, como em lead_reunioes_agendadas)
  rescue Ramon::ContratoApto::Proibido
    render json: { error: 'SEM_PERMISSAO' }, status: :forbidden
  rescue Ramon::ContratoApto::Invalido => e
    render json: { error: e.message == 'motivo' ? 'MOTIVO_OBRIGATORIO' : 'SITUACAO_INVALIDA' }, status: :unprocessable_entity
  end

  private

  def executar
    case params[:acao]
    when 'validar' then Ramon::ContratoApto.validar!(@lead, Current.user)
    when 'devolver' then Ramon::ContratoApto.devolver!(@lead, Current.user, params[:motivo])
    when 'reenviar' then Ramon::ContratoApto.reenviar!(@lead, Current.user)
    when 'designar' then Ramon::ContratoApto.designar!(@lead, Current.user, Current.account.users.find_by(id: params[:user_id]))
    end
  end

  def fetch_lead
    @lead = Current.account.leads.find(params[:id])
  end
end
