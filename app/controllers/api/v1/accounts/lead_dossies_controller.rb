class Api::V1::Accounts::LeadDossiesController < Api::V1::Accounts::BaseController
  before_action :fetch_lead

  def show
    authorize(@lead, :show?)
    render json: Ramon::DossieService.new(lead: @lead).perform
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:id])
  end
end
