class Api::V1::Accounts::LeadActivitiesController < Api::V1::Accounts::BaseController
  before_action :fetch_lead

  def index
    authorize(@lead, :show?)
    @activities = @lead.lead_activities
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end
end
