# ramon: Casos de teste da IA — conversas-modelo por assistente, com critério
# do que é resposta boa. Só administrador.
class Api::V1::Accounts::Captain::IaCasosController < Api::V1::Accounts::BaseController
  CRITERIOS = [:handoff, :rubrica, { deve_usar: [], nao_deve_usar: [], deve_conter: [], nao_pode_conter: [] }].freeze

  before_action :current_account
  before_action -> { authorize(Captain::IaCaso, :gerenciar?) }
  before_action :set_assistant
  before_action :set_caso, only: [:update, :destroy]

  def index
    casos = escopo.ordenados.to_a
    render json: { payload: casos, estimativa: Captain::IaRodada.estimativa(casos.count(&:ativo)) }
  end

  def create
    render json: escopo.create!(caso_params.merge(origem: 'usuario'))
  end

  def update
    @caso.update!(caso_params)
    render json: @caso
  end

  def destroy
    @caso.destroy!
    head :no_content
  end

  private

  def set_assistant
    @assistant = Captain::Assistant.for_account(Current.account.id).find(params[:assistant_id])
  end

  def set_caso
    @caso = escopo.find(params[:id])
  end

  def escopo
    Captain::IaCaso.where(account_id: Current.account.id, assistant_id: @assistant.id)
  end

  def caso_params
    params.require(:caso).permit(:titulo, :grupo, :ativo, mensagens: [:role, :content], criterios: CRITERIOS)
  end
end
