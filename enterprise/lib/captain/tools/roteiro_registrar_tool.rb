# Escrita interna (nada sai para o cliente): grava a resposta do lead num passo do roteiro. O motor faz a conta,
# escolhe a saida e aplica as consequencias fixas (etiqueta, etapa, Perdido, passar para a equipe).
class Captain::Tools::RoteiroRegistrarTool < Captain::Tools::RamonBaseTool
  # Texto que Ramon::Roteiro.descrever devolve quando o roteiro acaba de passar o caso para a equipe; o
  # AgentRunnerService trata isso como handoff (a conversa já saiu do bot e a resposta do turno não publicaria).
  HANDOFF = 'Roteiro encerrado: humano'.freeze

  description 'Registra a resposta do lead a um passo do roteiro da tese. Informe a chave do passo e o valor ' \
              '(sim/nao, uma das opcoes, numero, data AAAA-MM-DD ou texto). Em passo de texto livre, informe tambem ' \
              'o saida_id que melhor descreve a resposta. Devolve o proximo passo ou o desfecho.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead). Sem ele, usa o caso da conversa aberta.', required: false
  param :chave, type: 'string', desc: 'Chave do passo (vem do Passo atual do roteiro)', required: true
  param :valor, type: 'string', desc: 'Resposta do lead, no formato do passo', required: false
  param :saida_id, type: 'string', desc: 'Id da saida escolhida (passo de texto livre)', required: false

  def perform(tool_context, chave:, valor: nil, saida_id: nil, lead_id: nil)
    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    log_tool_usage('roteiro_registrar', { lead_id: lead.id, chave: chave })
    res = ::Ramon::Roteiro.registrar(lead, chave: chave, valor: valor, saida_id: saida_id)
    res[:erro] || ::Ramon::Roteiro.resumo(res)
  end
end
