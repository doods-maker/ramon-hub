# Tela Agentes: lista e responde os pedidos de permissão da esteira (ADR 0014). Mesma lista de acesso do painel.
class Api::V1::Accounts::RamonAprovacoesAgenteController < Api::V1::Accounts::BaseController
  before_action { head :forbidden unless Ramon::PainelAgentes.liberado?(Current.user) }

  def index
    render json: RamonAprovacaoAgente.pendentes.map { |pedido|
      pedido.as_json(only: %i[id caso ferramenta entrada created_at]).merge(nomes: Ramon::NomesAdvbox.da_entrada(pedido.entrada))
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
