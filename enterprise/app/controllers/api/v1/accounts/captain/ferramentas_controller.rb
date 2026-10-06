# ramon: tela Ferramentas (I-FE1/I-FE2) — o catálogo do config/agents/tools.yml
# com as skills ativas que usam cada ferramenta e o que Execuções registrou
# (última vez, execuções e erros em 7 dias). Leitura pura; admin + agente.
class Api::V1::Accounts::Captain::FerramentasController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action -> { authorize(:ramon_dashboard, :show?) }

  def index
    skills = skills_por_ferramenta
    runs = Captain::ToolRun.fora_de_teste.where(account_id: Current.account.id)
    ultimas = runs.group(:tool_name).maximum(:created_at)
    semana = runs.where(created_at: 7.days.ago..)
    execucoes = semana.group(:tool_name).count
    erros = semana.where(status: 'erro').group(:tool_name).count

    payload = Captain::Assistant.built_in_agent_tools.map do |tool|
      id = tool[:id]
      tool.merge(skills: skills.fetch(id, []), ultima_execucao_em: ultimas[id],
                 execucoes_7d: execucoes.fetch(id, 0), erros_7d: erros.fetch(id, 0))
    end
    render json: { payload: payload }
  end

  private

  def skills_por_ferramenta
    escopo = Captain::Scenario.enabled.where(account_id: Current.account.id).includes(:assistant).order(:id)
    escopo.each_with_object({}) do |skill, mapa|
      Array(skill.tools).each do |id|
        (mapa[id] ||= []) << { id: skill.id, title: skill.title, assistant_id: skill.assistant_id,
                               assistant_name: skill.assistant.name }
      end
    end
  end
end
