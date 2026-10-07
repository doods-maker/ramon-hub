# FORK-PONTO (ramon) — Inteligência A4 (I-X3): no painel do Copiloto da conversa, o assistente da EQUIPE
# (sem caixa conectada) com skills ligadas roda o MESMO agente do Testar (skills + ferramentas da banca),
# não o Captain::Copilot::ChatService do upstream (só busca conversa/contato/artigo). O de leads segue no upstream.
# Nada vai ao cliente: a resposta fica no painel; escrita no AdvBox segue a regra de ouro (prévia + "confirma?").
# Contexto do caso: Ramon::CopilotoPainel (LGPD). Uso e custo: source 'copiloto_painel'.
class Captain::Copilot::SkillsService
  ERRO = 'Não consegui responder agora. Tente de novo em instantes.'.freeze

  def self.usa?(assistant)
    assistant.account.feature_enabled?('captain_integration_v2') && assistant.inboxes.none? && assistant.scenarios.enabled.exists?
  end

  def initialize(assistant, conversation_id:, copilot_thread_id:)
    @assistant = assistant
    @conversation_id = conversation_id
    @thread = assistant.account.copilot_threads.find(copilot_thread_id)
  end

  def responder
    historico = Ramon::CopilotoPainel.com_contexto(@thread.previous_history, @assistant.account, @conversation_id)
    resposta = Captain::Assistant::AgentRunnerService.new(assistant: @assistant, source: 'copiloto_painel')
                                                     .generate_response(message_history: historico)
    @thread.copilot_messages.create!(message: { content: texto(resposta) }, message_type: :assistant)
  end

  private

  def texto(resposta)
    falhou = resposta['reasoning'].to_s.start_with?('Error occurred') || resposta['response'] == 'conversation_handoff'
    falhou ? ERRO : resposta['response'].to_s
  end
end
