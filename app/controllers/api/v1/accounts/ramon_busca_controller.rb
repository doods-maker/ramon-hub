# Paleta Ctrl K (redesign v2, Onda 5): busca local em leads + painel do cliente.
class Api::V1::Accounts::RamonBuscaController < Api::V1::Accounts::BaseController
  def show
    authorize(:ramon_dashboard, :show?)
    render json: Ramon::Busca.new(Current.account, params[:q]).perform
  end
end
