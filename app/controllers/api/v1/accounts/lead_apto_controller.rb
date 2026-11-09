# Contrato apto no painel do lead (Ramon::ContratoApto): o advogado da tese (ou o admin) valida ou devolve com motivo,
# o Closer reenvia depois de corrigir e o admin designa o advogado do lead (user_id vazio = volta para a tese). Quem vê
# o lead chega aqui; a regra de quem pode cada ação é do módulo (403 quando não pode, 422 quando o caso não está na
# situação certa). create.json.jbuilder devolve o lead (partial pelo caminho cheio, como em lead_reunioes_agendadas).
class Api::V1::Accounts::LeadAptoController < Api::V1::Accounts::BaseController
  before_action :fetch_lead

  def create
    authorize(@lead, :show?)
    case params[:acao]
    when 'validar' then Ramon::ContratoApto.validar!(@lead, Current.user)
    when 'devolver' then Ramon::ContratoApto.devolver!(@lead, Current.user, params[:motivo])
    when 'reenviar' then Ramon::ContratoApto.reenviar!(@lead, Current.user)
    when 'designar' then Ramon::ContratoApto.designar!(@lead, Current.user, validador)
    else erro('ACAO_INVALIDA')
    end
  rescue Ramon::ContratoApto::Proibido
    render json: { error: 'SEM_PERMISSAO' }, status: :forbidden
  rescue Ramon::ContratoApto::Invalido => e
    erro({ 'motivo' => 'MOTIVO_OBRIGATORIO', 'validador' => 'VALIDADOR_INVALIDO' }.fetch(e.message, 'SITUACAO_INVALIDA'))
  end

  private

  # Só gente da conta; id que não existe é erro (não volta para a tese em silêncio).
  def validador
    return if params[:user_id].blank?

    Current.account.users.find_by(id: params[:user_id]) || raise(Ramon::ContratoApto::Invalido, 'validador')
  end

  def erro(codigo)
    render json: { error: codigo }, status: :unprocessable_entity
  end

  def fetch_lead
    @lead = Current.account.leads.find(params[:id])
  end
end
