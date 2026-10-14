# Leitura: o passo do roteiro da tese que a IA pergunta agora (spec roteiro da tese §3.5). Toda a regra fica em
# Ramon::Roteiro (testada no CI); aqui só resolve o caso e devolve o texto.
class Captain::Tools::RoteiroPassoAtualTool < Captain::Tools::RamonBaseTool
  SEM_ROTEIRO = 'Esta tese nao tem roteiro. Siga a triagem de sempre (playbook da tese e registrar qualificacao).'.freeze

  description 'Diz o passo atual do roteiro de qualificacao da tese do caso: o que descobrir, como perguntar, as ' \
              'opcoes e o que ja foi respondido. Chame antes de cada pergunta de qualificacao.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead). Sem ele, usa o caso da conversa aberta.', required: false

  def perform(tool_context, lead_id: nil)
    # Testar com tese (F2): roteiro em teste, sem lead — nada é gravado.
    teste = tool_context.state&.dig(:roteiro_teste)
    return ::Ramon::Roteiro::Teste.atual(@assistant.account, teste) || SEM_ROTEIRO if teste

    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    atual = ::Ramon::Roteiro.atual(lead)
    return SEM_ROTEIRO if atual.nil?

    log_tool_usage('roteiro_passo_atual', { lead_id: lead.id })
    ::Ramon::Roteiro.descrever(atual[:passo], atual[:estado])
  end
end
