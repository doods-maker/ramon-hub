# Tela Execuções (Fatia 3 da área de IA): o que o agente executou, quando, com
# quais parâmetros e o que voltou. Leitura pura sobre Captain::ToolRun.
class Api::V1::Accounts::CaptainToolRunsController < Api::V1::Accounts::BaseController
  LIST_LIMIT = 100

  before_action :current_account
  before_action :check_authorization

  def index
    @tool_runs = escopo.recentes.limit(LIST_LIMIT)
    @resumo = resumo
  end

  private

  # Mesmas permissões do Centro de Comando (admin + agent).
  def check_authorization
    authorize(:ramon_dashboard, :show?)
  end

  def escopo
    runs = Captain::ToolRun.where(account_id: Current.account.id)
    runs = runs.where(tool_name: params[:tool_name]) if params[:tool_name].present?
    runs = runs.where(status: params[:status]) if params[:status].present?
    runs
  end

  def resumo
    desde = 24.hours.ago
    janela = Captain::ToolRun.where(account_id: Current.account.id, created_at: desde..)
    {
      total_24h: janela.count,
      erros_24h: janela.where(status: 'erro').count,
      por_tool: janela.group(:tool_name).count,
      tools: Captain::ToolRun.where(account_id: Current.account.id).distinct.pluck(:tool_name).sort
    }
  end
end
