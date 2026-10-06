# Tela Uso e custo (Inteligência): números do período, provedor/modelo em vigor por função e o
# teto diário em US$ do alerta de gasto. Só administrador. A troca de modelo por função usa a
# API captain/preferences (mecanismo do upstream) — a trava da assinatura mora no Account.
class Api::V1::Accounts::RamonIaUsoController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    render json: Ramon::IaUsoResumo.new(Current.account, params[:periodo].to_s).perform
  end

  # teto_diario_usd vazio = sem alerta.
  def update
    valor = params[:teto_diario_usd].presence
    teto = valor && Float(valor.to_s.tr(',', '.'), exception: false)
    return render json: { error: 'teto inválido' }, status: :unprocessable_entity if valor && (teto.nil? || teto.negative?)

    Current.account.update!(settings: (Current.account.settings || {}).merge(Ramon::IaGastoAlerta::CHAVE_TETO => teto))
    render json: { teto_diario_usd: teto }
  end

  private

  def check_authorization
    authorize(:ramon_ia, :gerenciar?)
  end
end
