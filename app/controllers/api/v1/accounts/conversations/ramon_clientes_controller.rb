# Painel do cliente na caixa do escritório (redesign v2) — ver Ramon::ClienteDaConversa.
class Api::V1::Accounts::Conversations::RamonClientesController < Api::V1::Accounts::Conversations::BaseController
  def show
    render json: Ramon::ClienteDaConversa.new(@conversation).perform
  end
end
