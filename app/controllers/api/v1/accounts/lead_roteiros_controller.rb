# Roteiro da tese no painel do lead (F2): o passo a passo e o "Reabrir roteiro".
class Api::V1::Accounts::LeadRoteirosController < Api::V1::Accounts::BaseController
  before_action :fetch_lead

  def show
    authorize(@lead, :show?)
    render json: Ramon::Roteiro::Painel.montar(@lead)
  end

  # Volta no passo que decidiu (Ramon::Roteiro.reabrir, F1). Lead ganho ou perdido não reabre por aqui — tirar do
  # Perdido no funil já reabre. Sugestões do roteiro pendentes no Cockpit deixam de valer (aprovar o Perdido depois
  # perderia um lead que voltou a ser qualificado).
  def reabrir
    authorize(@lead, :update?)
    return erro('Lead ganho ou perdido: o roteiro não reabre por aqui.') if @lead.won_at || @lead.lost_at
    return erro('O roteiro deste lead não está encerrado.') unless Ramon::Roteiro.reabrir(@lead)

    Current.account.copilot_suggestions.pending.where(lead_id: @lead.id).where("payload->>'origem' = 'roteiro'")
           .find_each { |sugestao| sugestao.update!(status: 'dismissed') }
    render json: Ramon::Roteiro::Painel.montar(@lead.reload)
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:id])
  end

  def erro(texto)
    render json: { error: texto }, status: :unprocessable_entity
  end
end
