class Api::V1::Accounts::LeadTasksController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_lead, if: -> { params[:lead_id].present? }
  before_action :fetch_task, only: [:update, :destroy, :complete]
  before_action :check_authorization

  def index
    @lead_tasks = params[:lead_id].present? ? @lead.lead_tasks.order(:due_at) : account_scope
  end

  def create
    @lead_task = @lead.lead_tasks.create!(permitted_params.merge(account: Current.account, user: Current.user))
  end

  def update
    @lead_task.update!(permitted_params)
  end

  def complete
    @lead_task.complete!(Current.user)
    render :update
  end

  def destroy
    @lead_task.destroy!
    head :ok
  end

  private

  def account_scope
    scope = Current.account.lead_tasks.includes(lead: [:sdr, :closer])
    case params[:scope]
    when 'overdue' then scope.overdue.order(:due_at)
    when 'today' then scope.due_today.order(:due_at)
    when 'agenda' then agenda_scope(scope).order(:due_at)
    else scope.open_tasks.order(:due_at)
    end
  end

  # Período da Agenda (from..to): abertas do período + concluídas hoje (a
  # Agenda mostra apagadas) + vencidas abertas de qualquer dia (fixadas em Hoje).
  def agenda_scope(scope)
    periodo = scope.where(due_at: Time.zone.parse(params[:from].to_s)..Time.zone.parse(params[:to].to_s))
    hoje = Time.current.in_time_zone('America/Sao_Paulo').all_day
    periodo.open_tasks.or(periodo.where(completed_at: hoje)).or(scope.overdue)
  end

  def fetch_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end

  def fetch_task
    @lead_task = @lead.lead_tasks.find(params[:id])
  end

  def permitted_params
    params.permit(:title, :kind, :due_at)
  end

  def check_authorization
    authorize(LeadTask)
  end
end
