# Escrita interna (nada sai para o cliente): grava a resposta do lead num passo do roteiro. O motor faz a conta,
# escolhe a saida e aplica as consequencias fixas (etiqueta, etapa, Perdido, passar para a equipe).
class Captain::Tools::RoteiroRegistrarTool < Captain::Tools::RamonBaseTool
  # Sinal no state da execucao: o roteiro acabou de passar o caso para a equipe (Efeitos.humano ja fez bot_handoff!).
  # O AgentRunnerService le o sinal e trata como handoff — nada depende do texto devolvido a IA.
  HANDOFF = :ramon_roteiro_handoff

  description 'Registra a resposta do lead a um passo do roteiro da tese. Informe a chave do passo e o valor ' \
              '(sim/nao, uma das opcoes, numero, data AAAA-MM-DD ou texto). Em passo de texto livre, informe tambem ' \
              'o saida_id que melhor descreve a resposta. Devolve o proximo passo ou o desfecho.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead). Sem ele, usa o caso da conversa aberta.', required: false
  param :chave, type: 'string', desc: 'Chave do passo (vem do Passo atual do roteiro)', required: true
  param :valor, type: 'string', desc: 'Resposta do lead, no formato do passo', required: false
  param :saida_id, type: 'string', desc: 'Id da saida escolhida (passo de texto livre)', required: false

  def perform(tool_context, chave: nil, valor: nil, saida_id: nil, lead_id: nil)
    res = no_roteiro(tool_context, lead_id) { |lead| ::Ramon::Roteiro.registrar(lead, chave: chave, valor: valor, saida_id: saida_id) }
    return res if res.is_a?(String) # SEM_LEAD

    tool_context.state[HANDOFF] = true if res[:handoff]
    tool_context.state[Captain::Tools::RoteiroPassoAtualTool::MOSTRADO] = res[:proximo]&.chave unless res[:erro]
    res[:erro] || ::Ramon::Roteiro.resumo(res)
  end
end
