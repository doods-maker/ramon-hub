# Ações nativas das regras do Chatwoot (etiqueta, atribuir, status, prioridade, e-mail…)
# executadas pelo mesmo código delas. A regra é só um molde em memória; a autoria dos
# eventos gerados vira a execução do fluxo (uma regra sem id não serializa no job).
class Ramon::Fluxos::AcaoChatwootService < AutomationRules::ActionService
  def initialize(execucao, conversation, acoes)
    permitidas = acoes.select { |a| Ramon::Fluxos::Grafo.permitidas_chatwoot.include?(a['action_name']) }
    molde = AutomationRule.new(account: conversation.account, name: execucao.fluxo.nome,
                               event_name: 'conversation_updated', conditions: [], actions: permitidas)
    super(molde, conversation.account, conversation)
    Current.executed_by = execucao
  end
end
