# "+ Tarefa" → Reunião no painel do lead: o mesmo efeito da reunião marcada
# pelo Cal.com (Ramon::ReuniaoAgendamento). Nada é enviado ao cliente — a
# confirmação nasce como nota RASCUNHO. update = Remarcar (task_id + starts_at);
# destroy = Cancelar (task_id). Lead com reunião aberta: 409 até force=true.
class Api::V1::Accounts::LeadReunioesAgendadasController < Api::V1::Accounts::BaseController
  before_action :set_lead
  before_action :check_starts_at, only: [:create, :update]

  def create
    return render_conflito if reuniao_aberta && !force?
    return render_ocupado unless force_ocupado? || Ramon::ReuniaoAgendamento.livre?(@lead, starts_at)

    title = params[:title].to_s.strip.presence || 'Reunião'
    Ramon::ReuniaoAgendamento.call(lead: @lead, starts_at: starts_at, title: title, user: Current.user, formato: formato || 'video')
    # leads/show usa o partial pelo nome curto, que não resolve fora do
    # LeadsController — template próprio aponta o partial pelo caminho cheio.
    @lead.reload
  end

  def update
    task = meeting_task
    return render_ocupado unless force_ocupado? || Ramon::ReuniaoAgendamento.livre?(@lead, starts_at, task: task)

    @lead_task = Ramon::ReuniaoAgendamento.remarcar(task: task, starts_at: starts_at, user: Current.user, formato: formato)
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
    return render json: { error: 'STARTS_AT_INVALIDO' }, status: :unprocessable_entity if starts_at.blank?

    render json: { error: 'FORMATO_INVALIDO' }, status: :unprocessable_entity if params[:formato].present? && formato.nil?
  end

  # force libera só o aviso de reunião aberta; force_ocupado, só o de horário ocupado.
  def force? = ActiveModel::Type::Boolean.new.cast(params[:force])

  def force_ocupado? = ActiveModel::Type::Boolean.new.cast(params[:force_ocupado])

  # nil = não veio (ou veio inválido, barrado no check_starts_at).
  def formato = params[:formato].presence_in(LeadTask::FORMATOS)

  def render_ocupado
    render json: { error: 'HORARIO_OCUPADO' }, status: :conflict
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
