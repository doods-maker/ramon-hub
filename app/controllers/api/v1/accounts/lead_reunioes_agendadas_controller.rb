# "+ Tarefa" → Reunião no painel do lead: o mesmo efeito da reunião marcada
# pelo Cal.com (Ramon::ReuniaoAgendamento). Nada é enviado ao cliente — a
# confirmação nasce como nota RASCUNHO. update = Remarcar (task_id + starts_at);
# destroy = Cancelar (task_id). Lead com reunião aberta: 409 até force=true.
class Api::V1::Accounts::LeadReunioesAgendadasController < Api::V1::Accounts::BaseController
  before_action :set_lead
  before_action :check_starts_at, only: [:create, :update]

  def create
    return render_conflito if reuniao_aberta && !ActiveModel::Type::Boolean.new.cast(params[:force])

    title = params[:title].to_s.strip.presence || 'Reunião'
    Ramon::ReuniaoAgendamento.call(lead: @lead, starts_at: starts_at, title: title, user: Current.user)
    # leads/show usa o partial pelo nome curto, que não resolve fora do
    # LeadsController — template próprio aponta o partial pelo caminho cheio.
    @lead.reload
  end

  def update
    @lead_task = Ramon::ReuniaoAgendamento.remarcar(task: meeting_task, starts_at: starts_at, user: Current.user)
  end

  def destroy
    Ramon::ReuniaoAgendamento.cancelar(task: meeting_task, user: Current.user)
    head :ok
  end

  private

  def set_lead
    @lead = Current.account.leads.find(params[:lead_id])
    authorize(@lead, :update?)
  end

  def check_starts_at
    render json: { error: 'STARTS_AT_INVALIDO' }, status: :unprocessable_entity if starts_at.blank?
  end

  def reuniao_aberta
    @reuniao_aberta ||= @lead.lead_tasks.open_tasks.where(kind: 'meeting').order(:due_at).first
  end

  def render_conflito
    render json: { error: 'REUNIAO_ABERTA', task: reuniao_aberta.slice(:id, :title, :due_at) }, status: :conflict
  end

  def meeting_task
    @lead.lead_tasks.open_tasks.find_by!(id: params[:task_id], kind: 'meeting')
  end

  def starts_at
    @starts_at ||= Time.zone.parse(params[:starts_at].to_s)
  rescue ArgumentError
    nil
  end
end
