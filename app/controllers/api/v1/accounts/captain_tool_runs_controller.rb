# Tela Execuções (Fatia 3 da área de IA): o que o agente executou, quando, com
# quais parâmetros e o que voltou. Leitura pura sobre Captain::ToolRun.
class Api::V1::Accounts::CaptainToolRunsController < Api::V1::Accounts::BaseController
  LIST_LIMIT = 100

  before_action :current_account
  before_action :check_authorization

  def index
    @tool_runs = escopo.recentes.limit(LIST_LIMIT).to_a
    @resumo = resumo
    # nome e nivel de cada ferramenta pra tela: o endpoint de ferramentas e so admin
    @catalogo = ChatwootApp.enterprise? ? Captain::Assistant.built_in_agent_tools : []
    @nomes = nomes(@tool_runs)
  end

  private

  # Mesmas permissões do Centro de Comando (admin + agent).
  def check_authorization
    authorize(:ramon_dashboard, :show?)
  end

  def escopo
    runs = Captain::ToolRun.fora_de_teste.where(account_id: Current.account.id)
    runs = runs.where(tool_name: params[:tool_name]) if params[:tool_name].present?
    runs = runs.where(status: params[:status]) if params[:status].present?
    runs
  end

  # I-EX2: nome do caso, nº da conversa (o que a rota da tela usa) e assistente
  # de cada linha — 3 consultas para as 100 linhas.
  def nomes(runs)
    {
      leads: Current.account.leads.where(id: runs.filter_map(&:lead_id)).pluck(:id, :name).to_h,
      conversas: Current.account.conversations.where(id: runs.filter_map(&:conversation_id)).pluck(:id, :display_id).to_h,
      assistentes: assistentes
    }
  end

  def assistentes
    return {} unless ChatwootApp.enterprise?

    Captain::Assistant.for_account(Current.account.id).pluck(:id, :name).to_h
  end

  def resumo
    desde = 24.hours.ago
    janela = Captain::ToolRun.fora_de_teste.where(account_id: Current.account.id, created_at: desde..)
    {
      total_24h: janela.count,
      erros_24h: janela.where(status: 'erro').count,
      por_tool: janela.group(:tool_name).count,
      tools: Captain::ToolRun.fora_de_teste.where(account_id: Current.account.id).distinct.pluck(:tool_name).sort
    }
  end
end
