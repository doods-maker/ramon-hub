class Api::V1::Accounts::LeadNotesController < Api::V1::Accounts::BaseController
  before_action :fetch_lead

  def index
    authorize(@lead, :show?)
    @notes = @lead.lead_notes
  end

  def create
    authorize(@lead, :show?)
    @note = @lead.lead_notes.create!(account: @lead.account, user: Current.user, body: params.require(:body))
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end
end
