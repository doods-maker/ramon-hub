class Api::V1::Accounts::LeadActivitiesController < Api::V1::Accounts::BaseController
  before_action :fetch_lead

  def index
    authorize(@lead, :show?)
    # includes(:user): o partial toca activity.user&.name por linha (N+1 na timeline).
    @activities = @lead.lead_activities.includes(:user)
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end
end
