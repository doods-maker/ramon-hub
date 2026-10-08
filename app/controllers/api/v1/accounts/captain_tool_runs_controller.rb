# Tela Execuções (Fatia 3 da área de IA): o que o agente executou, quando, com
# quais parâmetros e o que voltou. Leitura pura sobre Captain::ToolRun.
class Api::V1::Accounts::CaptainToolRunsController < Api::V1::Accounts::BaseController
  LIST_LIMIT = 100
  FILTROS = %i[tool_name status lead_id].freeze
  # I-EX3: período da lista ("hoje" no fuso de Brasília — o servidor roda em UTC)
  PERIODOS = {
    'hoje' => -> { Time.find_zone!('America/Sao_Paulo').now.all_day },
    '7d' => -> { 7.days.ago..Time.current },
    '30d' => -> { 30.days.ago..Time.current }
  }.freeze

  before_action :current_account
  before_action :check_authorization

  def index
    @tool_runs = escopo.recentes.limit(LIST_LIMIT).to_a
    @mais = @tool_runs.size == LIST_LIMIT
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

  # I-EX3/I-X8: ferramenta, status, caso, período e "carregar mais" (antes_de = id da última linha da tela).
  def escopo
    runs = Captain::ToolRun.fora_de_teste.where(account_id: Current.account.id)
    FILTROS.each { |campo| runs = runs.where(campo => params[campo]) if params[campo].present? }
    runs = runs.where(created_at: PERIODOS[params[:periodo]].call) if PERIODOS.key?(params[:periodo])
    params[:antes_de].present? ? runs.where(id: ...params[:antes_de].to_i) : runs
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
