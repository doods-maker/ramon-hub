# Conversas do hub de um cliente, para o Claude da recepção (conector MCP) montar o relatório pós-contato:
# acha o contato pelo celular (qualquer grafia BR) ou CPF, devolve as conversas recentes com mensagens do cliente,
# do escritório e notas privadas, e grava o relatório de volta como nota privada.
# Invariantes: caixa Equipe nunca entra (nem leitura nem escrita); senha nunca sai (Message#content_for_llm).
module Ramon::ConversasDoCliente
  DIAS_PADRAO = 30
  DIAS_MAX = 365
  LIMITE_MENSAGENS = 200
  LIMITE_CONTATOS = 5
  # ponytail: teto de payload = contatos × conversas × mensagens; com janela de 365 dias pode pesar no contexto do Claude.
  LIMITE_CONVERSAS = 10
  LIMITE_NOTA = 20_000
  MARCA_NOTA = '📋 Registrado pelo Claude (conector do hub)'.freeze

  module_function

  # dias: janela por data da mensagem (padrão 30, teto 365). Sem contato com o número → contatos: [].
  def ler(account, telefone_ou_cpf, dias: nil)
    contatos = Ramon::ContatoBusca.por_numero(account.contacts, telefone_ou_cpf)
    raise ArgumentError, 'informe o telefone com DDD ou o CPF do cliente (10+ dígitos)' if contatos.nil?

    desde = janela(dias).days.ago
    { desde: desde.to_date.iso8601, contatos: contatos.order(:id).limit(LIMITE_CONTATOS).map { |c| contato(account, c, desde) } }
  end

  def anotar(account, conversa_id, texto)
    raise ArgumentError, 'texto da nota vazio' if texto.to_s.strip.empty?
    raise ArgumentError, "nota longa demais (máximo #{LIMITE_NOTA} caracteres)" if texto.to_s.length > LIMITE_NOTA

    conversa = Ramon::Equipe.fora_da_caixa(account.conversations).find_by(display_id: conversa_id)
    raise ArgumentError, "conversa #{conversa_id} não encontrada" if conversa.nil?

    nota = Messages::MessageBuilder.new(nil, conversa, { content: "#{MARCA_NOTA}\n\n#{texto.strip}", private: true }).perform
    { conversa_id: conversa.display_id, nota_id: nota.id }
  end

  def janela(dias)
    return DIAS_PADRAO if dias.nil?

    numero = Integer(dias)
    raise ArgumentError, "dias precisa ser de 1 a #{DIAS_MAX}" unless numero.between?(1, DIAS_MAX)

    numero
  end

  def contato(account, contact, desde)
    { contato_id: contact.id, nome: contact.name, telefone: contact.phone_number, cpf: contact.cpf,
      casos: account.leads.where(contact_id: contact.id).includes(:thesis, :lead_stage).map { |l| caso(l) },
      conversas: Ramon::Equipe.fora_da_caixa(contact.conversations).where(last_activity_at: desde..)
                              .includes(:inbox, :assignee).order(last_activity_at: :desc).limit(LIMITE_CONVERSAS)
                              .map { |c| conversa(c, desde) } }
  end

  def caso(lead)
    { lead_id: lead.id, tese: lead.thesis&.name, etapa: lead.lead_stage&.name, ganho: lead.won_at.present?,
      perdido: lead.lost_at.present?, advbox_processo_id: lead.custom_attributes&.dig('advbox', 'lawsuits_id') }
  end

  # cortada: bateu o teto de mensagens — as mais antigas da janela ficaram de fora.
  def conversa(conversation, desde)
    registros = mensagens(conversation, desde)
    { conversa_id: conversation.display_id, caixa: conversation.inbox&.name, status: conversation.status,
      atendente: conversation.assignee&.name, cortada: registros.size == LIMITE_MENSAGENS,
      mensagens: registros.filter_map { |m| mensagem(m) } }
  end

  # Rascunho do Copiloto (Captain::Assistant) fica de fora: é sugestão não enviada. IS DISTINCT FROM mantém sender NULL.
  def mensagens(conversation, desde)
    conversation.messages.includes(:attachments, :sender).where(created_at: desde..).where.not(message_type: %i[activity template])
                .where("messages.sender_type IS DISTINCT FROM 'Captain::Assistant'")
                .reorder(created_at: :desc, id: :desc).limit(LIMITE_MENSAGENS).to_a.reverse
  end

  # content_for_llm: traz a transcrição do áudio e passa pelo filtro de senha.
  def mensagem(message)
    texto = message.content_for_llm
    return if texto.blank?

    { em: message.created_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m/%Y %H:%M'), de: papel(message),
      autor: message.sender.try(:name), texto: texto }
  end

  def papel(message)
    return 'nota' if message.private?

    message.incoming? ? 'cliente' : 'escritorio'
  end
end
