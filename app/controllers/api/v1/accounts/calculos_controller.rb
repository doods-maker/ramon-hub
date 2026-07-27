# Histórico da tela Cálculos: lista o que já foi calculado (cliente, tipo,
# data/hora), reabre um cálculo no estado exato e apaga registro indevido.
class Api::V1::Accounts::CalculosController < Api::V1::Accounts::BaseController
  LIMIT = 50

  before_action :current_account
  before_action :fetch_calculo, only: [:destroy, :reabrir]
  before_action :check_authorization

  def index
    calculos = Current.account.calculos.recentes.limit(LIMIT)
    calculos = calculos.do_cliente(params[:q].to_s.strip) if params[:q].present?
    render json: { payload: calculos.map { |calculo| linha(calculo) } }
  end

  def destroy
    @calculo.destroy!
    head :no_content
  end

  # Devolve o CNIS do cálculo ao caso de origem (o rascunho de quem calculou ou
  # o caso do cliente) — é o servidor que lê `lead.cnis` na hora de recalcular,
  # então restaurar só no browser não bastaria.
  def reabrir
    lead = @calculo.lead
    lead.update!(cnis: @calculo.cnis_snapshot) if @calculo.cnis_snapshot.present?
    render json: {
      lead_id: lead.id,
      tipo: @calculo.tipo,
      params: @calculo.snapshot['params'] || {},
      cnis: lead.cnis_detalhe
    }
  end

  private

  def fetch_calculo
    @calculo = Current.account.calculos.find(params[:id])
  end

  def linha(calculo)
    {
      id: calculo.id,
      tipo: calculo.tipo,
      lead_id: calculo.lead_id,
      segurado_nome: calculo.segurado_nome,
      segurado_cpf: calculo.segurado_cpf,
      der: calculo.der,
      created_at: calculo.created_at.iso8601,
      user_name: calculo.user&.name,
      # sem CNIS no snapshot, reabrir só devolve os campos digitados
      tem_cnis: calculo.cnis_snapshot.present?
    }
  end
end
