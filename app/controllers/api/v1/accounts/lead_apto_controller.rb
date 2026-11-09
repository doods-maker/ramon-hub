# Contrato apto no painel do lead (Ramon::ContratoApto): o advogado da tese (ou o admin) valida ou devolve com motivo,
# o Closer reenvia depois de corrigir e o admin designa o advogado do lead (user_id vazio = volta para a tese). Quem vê
# o lead chega aqui; a regra de quem pode cada ação é do módulo (403 quando não pode, 422 quando o caso não está na
# situação certa). create.json.jbuilder devolve o lead (partial pelo caminho cheio, como em lead_reunioes_agendadas).
class Api::V1::Accounts::LeadAptoController < Api::V1::Accounts::BaseController
  before_action :fetch_lead, only: [:create]

  # Lista "Aguardando validação": os casos que a pessoa pode validar (o admin vê todos, inclusive os devolvidos).
  def index
    authorize(Lead, :index?)
    render json: Ramon::ContratoApto.fila(Current.account, Current.user).map { |lead| item(lead) }
  end

  # Valida em lote; o que a pessoa não pode (ou já não aguarda) volta em recusados.
  def validar_lote
    authorize(Lead, :index?)
    render json: Ramon::ContratoApto.validar_lote!(Current.account, Current.user, Array(params[:ids]))
  end

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

  def item(lead)
    { id: lead.id, name: lead.name, tese: lead.thesis&.name, closer: lead.closer&.name, contrato_limpo_em: lead.contrato_limpo_em&.iso8601,
      validador_id: lead.validador_id, sem_validador: lead.validador_id.nil? && lead.thesis&.validador_ids.blank?,
      dias_restantes: dias_restantes(lead) }.merge(Ramon::ContratoApto.dados(lead))
  end

  # dias úteis que faltam até o prazo (0 = vence hoje); nil fora da fila
  def dias_restantes(lead)
    fim = Ramon::ContratoApto.prazo(lead)&.to_date
    hoje = Time.current.in_time_zone(Ramon::ContratoApto::ZONA).to_date
    fim && ((hoje + 1)..fim).count { |dia| Ramon::ContratoApto.dia_util?(dia) }
  end

  def erro(codigo)
    render json: { error: codigo }, status: :unprocessable_entity
  end

  def fetch_lead
    @lead = Current.account.leads.find(params[:id])
  end
end
