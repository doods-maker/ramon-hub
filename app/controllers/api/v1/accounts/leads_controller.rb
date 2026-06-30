class Api::V1::Accounts::LeadsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_lead, except: [:index, :create]
  before_action :check_authorization

  def index
    @leads = policy_scope(Current.account.leads)
  end

  def show; end

  def create
    @lead = Current.account.leads.create!(permitted_params)
  end

  def update
    @lead.update!(permitted_params)
  end

  def destroy
    @lead.destroy!
    head :ok
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:id])
  end

  def permitted_params
    params.permit(:name, :lead_stage_id, :benefit_type_id, :lead_priority_id,
                  :contact_id, :conversation_id, :sdr_id, :closer_id,
                  :position, :lost_reason, :value, :source, :notes)
  end
end
