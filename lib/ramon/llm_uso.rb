# Uso e custo da IA: grava cada chamada de LLM em ramon_llm_chamadas (LlmChamada).
# Pontos de gravação (únicos):
#   - Ramon::LlmClient.complete — copiloto, funções ramon e os fluxos (função deduzida);
#   - Integrations::LlmInstrumentation#instrument_llm_call e Captain::ToolInstrumentation
#     #instrument_tool_session — Captain::BaseTaskService e serviços do Llm::BaseAiService;
#   - Captain::ChatHelper (uma linha por mensagem do LLM) e o runner do agente v2.
# Regra de ouro: gravar NUNCA quebra a resposta da IA — qualquer erro aqui vira log.
module Ramon::LlmUso
  # feature_name da instrumentação do Captain → função na tela
  FUNCOES = {
    'summarize' => 'resumo', 'assistant' => 'atendimento', 'copilot' => 'copiloto_captain',
    'faq_generator' => 'documentos', 'faq_generation' => 'documentos', 'paginated_faq_generation' => 'documentos',
    'conversation_faq' => 'faq_conversa', 'contact_notes' => 'memoria_contato'
  }.freeze
  CAMPOS = %i[account_id funcao origem assistant_id provider model input_tokens output_tokens duracao_ms
              status erro conversation_id lead_id].freeze
  # source do runner do agente v2 → função na tela (o resto soma no Atendimento)
  FUNCAO_DO_AGENTE = { 'fluxo' => 'fluxo', 'copiloto_painel' => 'copiloto_painel' }.freeze

  module_function

  # Envolve a chamada: mede, grava e devolve o resultado intacto (erro da IA sobe igual).
  def medir(dados)
    inicio = agora_ms
    begin
      resultado = yield
    rescue StandardError => e
      registrar(dados.merge(status: 'erro', erro: e.message, duracao_ms: agora_ms - inicio))
      raise
    end
    registrar(dados.merge(duracao_ms: agora_ms - inicio), resultado)
    resultado
  end

  def registrar(dados, resultado = nil)
    dados = dados.merge(do_resultado(resultado))
    return if dados[:account_id].blank?

    Ramon::IaGastoAlerta.verificar(LlmChamada.create!(atributos(dados)))
  rescue StandardError => e
    Rails.logger.warn("[Ramon::LlmUso] uso não gravado: #{e.class}: #{e.message}")
  end

  # Mensagem do LLM vista pelo on_end_message (Captain::ChatHelper): só as do assistente têm tokens.
  def registrar_mensagem(message, dados)
    return unless message.respond_to?(:role) && message.role.to_s == 'assistant'

    registrar(dados.merge(funcao: funcao_captain(dados[:funcao]), model: message.model_id), message)
  rescue StandardError => e
    Rails.logger.warn("[Ramon::LlmUso] uso da mensagem não gravado: #{e.class}: #{e.message}")
  end

  # Runner do agente v2 (assistentes): uma linha por execução, tokens somados de todos os turnos.
  # Captain::ChatHelper (módulo no limite de tamanho): lê o contexto do próprio helper.
  def registrar_do_chat(helper, message)
    registrar_mensagem(message, { account_id: helper.send(:resolved_account_id),
                                  assistant_id: helper.instance_variable_get(:@assistant)&.id,
                                  funcao: helper.send(:feature_name), origem: helper.instance_variable_get(:@source) })
  end

  def registrar_agente(assistant:, result:, inicio:, source: nil, conversation: nil)
    registrar({ account_id: assistant.account_id, assistant_id: assistant.id, conversation_id: conversation&.id,
                funcao: FUNCAO_DO_AGENTE.fetch(source.to_s, 'atendimento'), origem: source, duracao_ms: agora_ms - inicio,
                model: Ramon::LlmEscolha.para(assistant.account, 'atendimento')[:model] }.merge(do_agente(result)))
  rescue StandardError => e
    Rails.logger.warn("[Ramon::LlmUso] uso do agente não gravado: #{e.class}: #{e.message}")
  end

  def de_instrumentacao(params)
    metadata = params[:metadata] || {}
    { account_id: params[:account_id], funcao: funcao_captain(params[:feature_name]), model: params[:model],
      assistant_id: metadata[:assistant_id], origem: metadata[:source] }
  end

  # LlmClient chamado sem função/conta: deduz pelo arquivo de quem chamou e pela execução
  # de fluxo em andamento (Current.executed_by — os fluxos não passam nada).
  def contexto(caminho)
    base = { funcao: funcao_do_arquivo(caminho), account_id: Current.account&.id }
    execucao = Current.executed_by
    return base unless execucao.is_a?(FluxoExecucao)

    base.merge(funcao: 'fluxo', account_id: execucao.account_id, origem: execucao.ensaio ? 'teste' : 'fluxo')
  end

  def custo(model, entrada, saida)
    return if model.blank?

    info = RubyLLM.models.find(model)
    return if info.input_price_per_million.nil? || info.output_price_per_million.nil?

    ((entrada * info.input_price_per_million) + (saida * info.output_price_per_million)) / 1_000_000.0
  rescue RubyLLM::ModelNotFoundError
    nil
  end

  def atributos(dados)
    entrada = dados[:input_tokens].to_i
    saida = dados[:output_tokens].to_i
    dados.slice(*CAMPOS).merge(
      input_tokens: entrada, output_tokens: saida, status: dados[:status] || 'ok', origem: dados[:origem].presence || 'real',
      funcao: dados[:funcao].presence || 'outra', erro: dados[:erro]&.to_s&.truncate(250), custo_usd: custo(dados[:model], entrada, saida)
    )
  end

  # Tokens do que a chamada devolveu: RubyLLM::Message / LlmClient::Result, ou o hash
  # { message:, usage: { 'prompt_tokens', 'completion_tokens' }, error: } das tarefas.
  def do_resultado(resultado)
    return { input_tokens: resultado.input_tokens, output_tokens: resultado.output_tokens } if resultado.respond_to?(:input_tokens)
    return {} unless resultado.is_a?(Hash)

    uso = (resultado[:usage] || {}).to_h.stringify_keys
    { input_tokens: uso['prompt_tokens'], output_tokens: uso['completion_tokens'] }
      .merge(resultado[:error] ? { status: 'erro', erro: resultado[:error] } : {})
  end

  def do_agente(result)
    return { status: 'erro', erro: 'runner falhou' } if result.nil?

    { input_tokens: result.usage&.input_tokens, output_tokens: result.usage&.output_tokens,
      status: result.error ? 'erro' : 'ok', erro: result.error&.message }
  end

  def funcao_captain(nome) = FUNCOES.fetch(nome.to_s, nome.to_s)

  def funcao_do_arquivo(caminho)
    return 'fluxo' if caminho.to_s.include?('/fluxos/')

    File.basename(caminho.to_s, '.rb').delete_suffix('_service').delete_suffix('_job').presence || 'outra'
  end

  def agora_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
end
