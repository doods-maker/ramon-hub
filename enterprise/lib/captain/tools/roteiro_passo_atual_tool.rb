# Leitura: o passo do roteiro da tese que a IA pergunta agora (spec roteiro da tese §3.5). Toda a regra fica em
# Ramon::Roteiro (testada no CI); aqui só resolve o caso (real ou do Testar) e devolve o texto.
class Captain::Tools::RoteiroPassoAtualTool < Captain::Tools::RamonBaseTool
  SEM_ROTEIRO = 'Esta tese nao tem roteiro. Siga a triagem de sempre (playbook da tese e registrar qualificacao).'.freeze
  # Sinal no state da execucao: a chave do ultimo passo que as tools do roteiro mostraram a IA neste turno. O
  # ResponseBuilderJob so poe botoes na resposta quando a pergunta e desse passo (Ramon::Roteiro::Opcoes).
  MOSTRADO = :ramon_roteiro_passo_mostrado

  description 'Diz o passo atual do roteiro de qualificacao da tese do caso: o que descobrir, como perguntar, as ' \
              'opcoes e o que ja foi respondido. Chame antes de cada pergunta de qualificacao.'
  param :lead_id, type: 'string', desc: 'Id do caso (lead). Sem ele, usa o caso da conversa aberta.', required: false

  def perform(tool_context, lead_id: nil)
    no_roteiro(tool_context, lead_id) do |lead|
      atual = ::Ramon::Roteiro.atual(lead)
      next SEM_ROTEIRO if atual.nil?

      tool_context.state[MOSTRADO] = atual[:passo]&.chave
      ::Ramon::Roteiro.descrever(atual[:passo], atual[:estado])
    end
  end
end
