class Api::V1::Accounts::TriageAgentsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_agent, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @triage_agents = Current.account.triage_agents.order(:id)
  end

  def show; end

  def create
    @triage_agent = Current.account.triage_agents.create!(permitted_params)
    render :show
  end

  def update
    @triage_agent.update!(permitted_params)
    render :show
  end

  def destroy
    @triage_agent.destroy!
    head :ok
  end

  private

  def fetch_agent
    @triage_agent = Current.account.triage_agents.find(params[:id])
  end

  def permitted_params
    params.permit(:name, :description, :area, :system_prompt, :kit_system_prompt, :provider, :model, :sensitive,
                  :active)
  end
end
