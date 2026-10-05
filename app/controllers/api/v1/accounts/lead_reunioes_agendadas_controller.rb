# "+ Tarefa" → Reunião no painel do lead: o mesmo efeito da reunião marcada
# pelo Cal.com (Ramon::ReuniaoAgendamento). Nada é enviado ao cliente — a
# confirmação nasce como nota RASCUNHO. update = Remarcar (task_id + starts_at).
class Api::V1::Accounts::LeadReunioesAgendadasController < Api::V1::Accounts::BaseController
  before_action :set_lead
  before_action :check_starts_at, only: [:create, :update]

  def create
    title = params[:title].to_s.strip.presence || 'Reunião'
    Ramon::ReuniaoAgendamento.call(lead: @lead, starts_at: starts_at, title: title, user: Current.user)
    # leads/show usa o partial pelo nome curto, que não resolve fora do
    # LeadsController — template próprio aponta o partial pelo caminho cheio.
    @lead.reload
  end

  def update
    @lead_task = Ramon::ReuniaoAgendamento.remarcar(task: meeting_task, starts_at: starts_at, user: Current.user)
  end

  private

  def set_lead
    @lead = Current.account.leads.find(params[:lead_id])
    authorize(@lead, :update?)
  end

  def check_starts_at
    render json: { error: 'STARTS_AT_INVALIDO' }, status: :unprocessable_entity if starts_at.blank?
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
