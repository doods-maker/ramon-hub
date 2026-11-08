# Pedidos de permissão da esteira (ADR 0014). Ver: mesma lista do painel. Decidir: só RAMON_AGENTES_DECISORES_EMAILS (ADR 0016).
class Api::V1::Accounts::RamonAprovacoesAgenteController < Api::V1::Accounts::BaseController
  before_action { head :forbidden unless Ramon::PainelAgentes.liberado?(Current.user) }
  before_action(only: :update) { head :forbidden unless Ramon::PainelAgentes.decide?(Current.user) }

  def index
    render json: {
      pode_decidir: Ramon::PainelAgentes.decide?(Current.user),
      pedidos: RamonAprovacaoAgente.pendentes.map do |pedido|
        pedido.as_json(only: %i[id caso ferramenta entrada created_at]).merge(nomes: Ramon::NomesAdvbox.da_entrada(pedido.entrada))
      end
    }
  end

  def update
    RamonAprovacaoAgente.find(params[:id]).decidir!(params.require(:decisao), Current.user, motivo: params[:motivo])
    head :no_content
  rescue ArgumentError
    head :unprocessable_entity
  rescue RamonAprovacaoAgente::JaDecidida
    head :conflict
  end
end
