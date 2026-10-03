# Equipe · chegada de cliente: Recepção avisa, destinatário responde. A busca de
# cliente no ADVBOX reusa ramon_calculos#advbox_customers.
class Api::V1::Accounts::RamonChegadasController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization

  def index
    chegadas = Current.account.chegadas.de_hoje.includes(:criado_por, :destinatario).order(:created_at)
    chegadas = chegadas.where('criado_por_id = :id OR destinatario_id = :id', id: Current.user.id) unless pode_avisar?
    render json: { payload: chegadas.map(&:push_event_data), pode_avisar: pode_avisar? }
  end

  def create
    chegada = Current.account.chegadas.create!(
      chegada_params.merge(criado_por: Current.user, destinatario: Current.account.users.find(params[:destinatario_id]))
    )
    Ramon::ChegadaEscalarJob.set(wait: Chegada::ESCALAR_APOS).perform_later(chegada.id)
    render json: chegada.push_event_data
  end

  def responder
    chegada = Current.account.chegadas.where(destinatario: Current.user).find(params[:id])
    chegada.update!(resposta: params.require(:resposta), respondido_em: Time.current)
    render json: chegada.push_event_data
  end

  def agenda
    render json: { payload: Ramon::AgendaHojeService.new(Current.account).perform }
  rescue Ramon::AdvboxClient::UnavailableError
    render json: { error: 'ADVBOX_UNAVAILABLE' }, status: :service_unavailable
  end

  private

  def pode_avisar?
    return @pode_avisar if defined?(@pode_avisar)

    @pode_avisar = Current.account_user.administrator? || Chegada.recepcao?(Current.account, Current.user)
  end

  def chegada_params
    params.permit(:cliente_nome, :motivo, :advbox_customer_id, :advbox_post_id)
  end

  def check_authorization
    authorize(:ramon_chegada, :"#{action_name}?")
  end
end
