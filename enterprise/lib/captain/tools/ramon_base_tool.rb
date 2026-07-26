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

  def data_iso(valor)
    Date.iso8601(valor.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
