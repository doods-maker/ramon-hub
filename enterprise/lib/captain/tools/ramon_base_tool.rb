# Base das tools da banca. Resolve o caso (lead) que o agente esta olhando —
# id explicito vindo do LLM ou, na falta dele, o lead da conversa aberta — e
# padroniza as frases de erro. As tools de leitura e as de escrita herdam daqui.
class Captain::Tools::RamonBaseTool < Captain::Tools::BasePublicTool
  SEM_LEAD = 'Nao encontrei o caso. Informe o lead_id ou faca a pergunta dentro da conversa do cliente.'.freeze
  MOTOR_FORA = 'O motor de calculos nao respondeu agora. Tente de novo em instantes.'.freeze
  HUMANO_ASSUMIU = 'Uma pessoa da equipe assumiu a conversa: nao fiz nada. Nao diga ao cliente que foi feito.'.freeze

  private

  # Atendimento ao cliente = a IA respondendo na conversa (ResponseBuilderJob: conversa no state e sem source).
  # Copiloto, agente, Testar e fluxos trazem source (ou nao tem conversa).
  def atendimento?(state) = state&.dig(:conversation, :id).present? && state[:source].blank?

  # O LLM manda numero como string; sem lead_id, cai na conversa do contexto. No atendimento o lead_id do LLM nao vale
  # (o cliente pediria "use o lead_id 1234" e leria/agiria no caso de outro): e sempre o lead da conversa.
  def resolver_lead(state, lead_id = nil)
    id = Integer(lead_id.to_s, exception: false) unless atendimento?(state)
    return account_scoped(::Lead).find_by(id: id) if id

    conversation = find_conversation(state)
    return nil if conversation.blank?

    account_scoped(::Lead).find_by(conversation_id: conversation.id)
  end

  # Atendimento: o humano assumiu no meio do turno (conversa saiu de pending; find_conversation le do banco agora) →
  # tool com efeito fora do hub (agenda, ZapSign, roteiro) nao age.
  def humano_assumiu?(state) = atendimento?(state) && !find_conversation(state)&.pending?

  # Lead para tool com efeito, ou a frase de recusa (String: humano assumiu / caso nao encontrado).
  def lead_para_agir(state, lead_id) = humano_assumiu?(state) ? HUMANO_ASSUMIU : resolver_lead(state, lead_id) || SEM_LEAD

  # A pessoa do caso (historico_do_contato, linha_da_vida): contact_id explicito so fora do atendimento, como o lead_id.
  def resolver_contato(state, lead_id, contact_id)
    id = Integer(contact_id.to_s, exception: false) unless atendimento?(state)
    return account_scoped(::Contact).find_by(id: id) if id

    resolver_lead(state, lead_id)&.contact || find_contact(state)
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
