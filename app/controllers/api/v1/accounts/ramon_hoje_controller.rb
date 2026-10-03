# Tela "Hoje" por papel (redesign v2, Onda 3) — o papel sai do backend.
class Api::V1::Accounts::RamonHojeController < Api::V1::Accounts::BaseController
  def show
    authorize(:ramon_dashboard, :show?)
    render json: Ramon::Hoje.new(account: Current.account, user: Current.user).perform
  end
end
