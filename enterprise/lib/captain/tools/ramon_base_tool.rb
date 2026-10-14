# Base das tools da banca. Resolve o caso (lead) que o agente esta olhando —
# id explicito vindo do LLM ou, na falta dele, o lead da conversa aberta — e
# padroniza as frases de erro. As tools de leitura e as de escrita herdam daqui.
class Captain::Tools::RamonBaseTool < Captain::Tools::BasePublicTool
  SEM_LEAD = 'Nao encontrei o caso. Informe o lead_id ou faca a pergunta dentro da conversa do cliente.'.freeze
  MOTOR_FORA = 'O motor de calculos nao respondeu agora. Tente de novo em instantes.'.freeze

  private

  # O LLM manda numero como string; sem lead_id, cai na conversa do contexto.
  def resolver_lead(state, lead_id = nil)
    id = Integer(lead_id.to_s, exception: false)
    return account_scoped(::Lead).find_by(id: id) if id

    conversation = find_conversation(state)
    return nil if conversation.blank?

    account_scoped(::Lead).find_by(conversation_id: conversation.id)
  end

  # Roteiro do caso — ou, no Testar com roteiro (F2), o lead descartável de Ramon::Roteiro::Teste: as tools do roteiro
  # rodam pelo mesmo caminho e só o lead muda (nada fica gravado no teste).
  def no_roteiro(tool_context, lead_id, &)
    teste = tool_context.state&.dig(:roteiro_teste)
    return ::Ramon::Roteiro::Teste.com_lead(@assistant.account, teste, &) if teste

    lead = resolver_lead(tool_context.state, lead_id)
    return SEM_LEAD if lead.blank?

    yield lead
  end

  def data_iso(valor)
    Date.iso8601(valor.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
