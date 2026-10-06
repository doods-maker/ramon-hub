class Api::V1::Accounts::LeadDossiesController < Api::V1::Accounts::BaseController
  before_action :fetch_lead

  def show
    authorize(@lead, :show?)
    render json: Ramon::DossieService.new(lead: @lead).perform
  end

  # "Dossiê entregue" ao jurídico (Painel do time): idempotente — a 1ª marca vale.
  def entregue
    authorize(@lead, :show?)
    @lead.lead_activities.find_or_create_by!(kind: 'dossie_entregue') do |marca|
      marca.account = @lead.account
      marca.user = Current.user
    end
    render json: Ramon::DossieService.new(lead: @lead).perform
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:id])
  end
end
