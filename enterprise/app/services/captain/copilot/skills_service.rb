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
    @copilot_thread_id = copilot_thread_id
  end

  # Sempre deixa uma resposta no painel (o "pensando" não fica girando) e não sobe o erro:
  # retry do Sidekiq rodaria o agente de novo (pagaria duas vezes). Exceção: a thread ainda não
  # existe (job enfileirado antes do commit em copilot_threads#create) — o find fica FORA do rescue,
  # RecordNotFound sobe e o Sidekiq tenta de novo antes de qualquer custo de LLM.
  def responder
    thread = @assistant.account.copilot_threads.find(@copilot_thread_id)
    begin
      thread.copilot_messages.create!(message: turno(thread), message_type: :assistant)
    rescue StandardError => e
      Rails.logger.error("[Captain::Copilot::SkillsService] painel sem resposta: #{e.class}: #{e.message}")
      thread.copilot_messages.create(message: { content: ERRO }, message_type: :assistant)
    end
  end

  private

  def turno(thread)
    mensagens = Ramon::CopilotoPainel.com_contexto(historico(thread), @assistant.account, @conversation_id)
    resposta = Captain::Assistant::AgentRunnerService.new(assistant: @assistant, source: 'copiloto_painel')
                                                     .generate_response(message_history: mensagens)
    { content: texto(resposta), agent_name: resposta['agent_name'] }.compact
  end

  # Como o Testar: agent_name em cada resposta, para o runner devolver o turno à skill dona
  # (prévia → "confirma?" → "sim" volta para a mesma skill, que grava no AdvBox).
  def historico(thread)
    thread.copilot_messages.where(message_type: %w[user assistant]).order(:created_at).map do |item|
      { role: item.message_type, content: item.message['content'], agent_name: item.message['agent_name'] }.compact
    end
  end

  def texto(resposta)
    return ERRO if resposta['reasoning'].to_s.start_with?('Error occurred') || resposta['response'] == 'conversation_handoff'

    resposta['response'].to_s.presence || ERRO
  end
end
