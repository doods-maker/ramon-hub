class Api::V1::Accounts::RamonPosVendaController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization

  def show
    @dados = Ramon::LeadRadar.pos_venda(Current.account)
  end

  private

  # Mesmas permissões do Centro de Comando (admin + agent).
  def check_authorization
    authorize(:ramon_dashboard, :show?)
  end
end
