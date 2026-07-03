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
    scope = Current.account.lead_tasks.includes(:lead)
    case params[:scope]
    when 'overdue' then scope.overdue.order(:due_at)
    when 'today' then scope.due_today.order(:due_at)
    else scope.open_tasks.order(:due_at)
    end
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
