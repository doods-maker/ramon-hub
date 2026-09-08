class Cliente::PainelController < Cliente::BaseController
  before_action :require_cliente

  def show
    head :ok
  end
end
