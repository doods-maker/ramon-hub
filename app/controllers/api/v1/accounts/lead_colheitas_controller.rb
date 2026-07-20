# Colheita SOB DEMANDA (decisão do Eduardo 20/07): o botão do painel do lead
# dispara a extração da conversa em background — não roda mais automático a cada
# mensagem. O resultado chega no painel pelo broadcast (custom_attributes.colheita).
# O service se auto-protege (só extrai tese com colheita + conversa presente).
class Api::V1::Accounts::LeadColheitasController < Api::V1::Accounts::BaseController
  before_action :fetch_lead

  def create
    authorize(@lead, :show?)
    Ramon::ColheitaExtractionJob.perform_later(lead_id: @lead.id)
    head :accepted
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end
end
