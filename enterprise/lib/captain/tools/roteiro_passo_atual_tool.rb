# Leitura: o passo do roteiro da tese que a IA pergunta agora (spec roteiro da tese §3.5). Toda a regra fica em
# Ramon::Roteiro (testada no CI); aqui só resolve o caso (real ou do Testar) e devolve o texto.
class Captain::Tools::RoteiroPassoAtualTool < Captain::Tools::RamonBaseTool
  SEM_ROTEIRO = 'Esta tese nao tem roteiro. Siga a triagem de sempre (playbook da tese e registrar qualificacao).'.freeze

  description 'Diz o passo atual do roteiro de qualificacao da tese do caso: o que descobrir, como perguntar, as ' \
              'opcoes e o que ja foi respondido. Chame antes de cada pergunta de qualificacao.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead). Sem ele, usa o caso da conversa aberta.', required: false

  def perform(tool_context, lead_id: nil)
    no_roteiro(tool_context, lead_id) { |lead| ::Ramon::Roteiro.texto_atual(lead) || SEM_ROTEIRO }
  end
end
