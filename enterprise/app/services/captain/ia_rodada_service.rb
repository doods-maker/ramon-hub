# Roda os casos de teste ativos de um assistente, um por vez, em modo teste
# (source 'teste': só consulta executa — ver BasePublicTool). Sem conversa: o
# agente recebe só as falas do caso. Grava o progresso na rodada a cada caso.
class Captain::IaRodadaService
  TIMEOUT_CASO = 120

  def initialize(rodada)
    @rodada = rodada
  end

  def perform
    inicio = agora
    @rodada.update!(status: 'rodando', total: casos.count, resultados: [], passou: 0, falhou: 0)
    casos.each { |caso| registrar(rodar(caso)) }
    @rodada.update!(status: 'concluida', duracao_ms: ms_desde(inicio))
  rescue StandardError => e
    @rodada.update!(status: 'erro', erro: "#{e.class}: #{e.message}".truncate(500), duracao_ms: ms_desde(inicio))
  end

  private

  def casos
    Captain::IaCaso.ativos.where(assistant_id: @rodada.assistant_id).ordenados
  end

  def rodar(caso)
    inicio = agora
    saida = Timeout.timeout(TIMEOUT_CASO) { executar(caso) }
    avaliacao = saida[:erro] ? { passou: false, motivos: [saida[:erro]] } : Captain::IaAvaliadorService.new(caso, saida).avaliar
    resultado(caso, saida, avaliacao, inicio)
  rescue Timeout::Error
    resultado(caso, saida_vazia, { passou: false, motivos: ["Passou de #{TIMEOUT_CASO}s"] }, inicio)
  end

  def executar(caso)
    ferramentas = []
    coletor = ->(nome, retorno, *) { ferramentas << { nome: nome.to_s.split('-').last, resultado: retorno.to_s.truncate(500) } }
    runner = Captain::Assistant::AgentRunnerService.new(assistant: @rodada.assistant, source: 'teste',
                                                        callbacks: { on_tool_complete: coletor })
    saida(runner.generate_response(message_history: caso.message_history), ferramentas)
  end

  # O runner engole exceção e devolve reasoning "Error occurred: ..." com
  # response 'conversation_handoff' — isso é erro do caso, não handoff.
  def saida(resposta, ferramentas)
    texto = resposta['response'].to_s
    erro = resposta['reasoning'].to_s.start_with?('Error occurred') ? "Erro do agente: #{resposta['reasoning']}".truncate(300) : nil
    handoff = resposta['handoff_tool_called'] == true || ferramentas.any? { |tool| tool[:nome] == 'handoff' } ||
              (erro.nil? && texto == 'conversation_handoff')
    { resposta: texto, ferramentas: ferramentas, handoff: handoff, erro: erro }
  end

  def saida_vazia
    { resposta: '', ferramentas: [], handoff: false }
  end

  def resultado(caso, saida, avaliacao, inicio)
    { caso_id: caso.id, titulo: caso.titulo, passou: avaliacao[:passou], motivos: avaliacao[:motivos],
      resposta: saida[:resposta], ferramentas: saida[:ferramentas], handoff: saida[:handoff], duracao_ms: ms_desde(inicio) }
  end

  def registrar(item)
    contador = item[:passou] ? :passou : :falhou
    @rodada.update!({ 'resultados' => @rodada.resultados + [item.as_json], contador.to_s => @rodada.public_send(contador) + 1 })
  end

  def agora
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def ms_desde(inicio)
    ((agora - inicio) * 1000).round
  end
end
