class Api::V1::Accounts::Captain::ScenariosController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action -> { check_authorization(Captain::Scenario) }
  before_action :set_assistant
  before_action :set_scenario, only: [:show, :update, :destroy]

  def index
    # ramon: ligadas e desligadas (I-SK4) — a tela separa em abas; o agente segue só com as ligadas.
    @scenarios = assistant_scenarios.order(enabled: :desc, id: :asc)
    @uso = uso_30d
  end

  def show; end

  def create
    @scenario = assistant_scenarios.create!(scenario_params.merge(account: Current.account, edited: true))
  end

  # ramon: tudo que passa pela tela é "editada" (I-SK5: o seed não mexe mais).
  # Desligar nunca esbarra na validação: instrução antiga pode citar ferramenta que saiu do catálogo.
  def update
    @scenario.assign_attributes(scenario_params.merge(edited: true))
    @scenario.save!(validate: !so_desligando?)
  end

  def destroy
    @scenario.destroy
    head :no_content
  end

  private

  def set_assistant
    @assistant = account_assistants.find(params[:assistant_id])
  end

  def account_assistants
    @account_assistants ||= Current.account.captain_assistants
  end

  def set_scenario
    @scenario = assistant_scenarios.find(params[:id])
  end

  def assistant_scenarios
    @assistant.scenarios
  end

  def so_desligando?
    scenario_params.keys == ['enabled'] && !@scenario.enabled
  end

  # ramon (I-SK7): quantas vezes cada ferramenta deste assistente rodou no atendimento de verdade em 30 dias —
  # Testar (playground) e Casos de teste não contam. A tela soma as ferramentas de cada skill.
  def uso_30d
    Captain::ToolRun.fora_de_teste
                    .where(account_id: Current.account.id, assistant_id: @assistant.id, created_at: 30.days.ago..)
                    .where("#{Captain::ToolRun.table_name}.source IS DISTINCT FROM 'playground'")
                    .group(:tool_name).count
  end

  def scenario_params
    params.require(:scenario).permit(:title, :description, :instruction, :enabled, :exemplo, tools: [], papeis: [])
  end
end
