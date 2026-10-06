# Execuções de um fluxo (lista e uma com a trilha) — base da tela "caminho aceso".
class Api::V1::Accounts::RamonFluxoExecucoesController < Api::V1::Accounts::BaseController
  LIMITE = 100

  before_action { authorize(:ramon_fluxo, :gerenciar?) }

  def index
    execucoes = fluxo.execucoes.includes(:versao, :alvo).order(created_at: :desc).limit(LIMITE)
    execucoes = execucoes.where(status: params[:status]) if params[:status].present?
    render json: { payload: execucoes.map(&:resumo_json) }
  end

  def show
    execucao = fluxo.execucoes.find(params[:id])
    render json: execucao.resumo_json.merge(grafo: execucao.contexto['grafo'] || execucao.versao&.grafo)
  end

  private

  def fluxo = @fluxo ||= Current.account.fluxos.find(params[:ramon_fluxo_id])
end
