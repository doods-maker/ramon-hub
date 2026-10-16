# Desfazer uma ação automática do funil (botão "Desfazer" do chip "IA: …" no card).
class Api::V1::Accounts::FunilAcoesController < Api::V1::Accounts::BaseController
  before_action :fetch_lead

  def desfazer
    authorize(@lead, :update?)
    acao = @lead.funil_acoes.reais.find(params[:id])
    return render json: { error: 'JA_DESFEITA' }, status: :unprocessable_entity unless acao.desfazer!(Current.user)

    @lead.reload
  end

  private

  def fetch_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end
end
