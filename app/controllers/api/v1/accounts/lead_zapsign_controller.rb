# Item 21 (fluxo A): botão "Gerar contrato" no painel do lead → ZapSign cria
# contrato + procuração pré-preenchidos e devolve o link de assinatura.
class Api::V1::Accounts::LeadZapsignController < Api::V1::Accounts::BaseController
  before_action :fetch_lead

  def create
    authorize(@lead, :show?)
    render json: Ramon::ZapsignContractService.new(@lead).perform
  rescue Ramon::ZapsignClient::RequestError => e
    render json: { error: e.body.to_s.truncate(300) }, status: :unprocessable_entity
  rescue Ramon::ZapsignClient::UnavailableError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end
end
