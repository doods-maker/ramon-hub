# Desfazer uma ação automática do funil (botão "Desfazer" do chip "IA: …" no card).
class Api::V1::Accounts::FunilAcoesController < Api::V1::Accounts::BaseController
  before_action :fetch_lead

  def desfazer
    authorize(@lead, :update?)
    acao = @lead.funil_acoes.reais.find(params[:id])
    return recusar(acao) unless acao.desfazer!(Current.user)

    @lead.reload
  end

  private

  def recusar(acao)
    return render json: { error: 'JA_DESFEITA', message: 'Essa ação já foi desfeita.' }, status: :unprocessable_entity if acao.desfeita_em

    render json: { error: 'LEAD_MOVIDO', message: 'O lead já foi movido depois dessa ação — desfaça à mão.' },
           status: :unprocessable_entity
  end

  def fetch_lead
    @lead = Current.account.leads.find(params[:lead_id])
  end
end
