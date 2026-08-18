# Tudo que o agente do hub (Claude na VPS) precisa ler de uma conversa, num JSON só:
# mensagens (com transcrições/anexos por nome), contato, lead (DossieService) e ids do ADVBOX.
class Ramon::AgenteContextoService
  LIMITE_MENSAGENS = 200

  def initialize(conversation)
    @conversation = conversation
    @lead = conversation.account.leads.find_by(conversation_id: conversation.id)
    @contact = conversation.contact
  end

  def perform
    {
      conversa: { id: @conversation.display_id, status: @conversation.status, inbox: @conversation.inbox&.name, mensagens: mensagens },
      contato: contato
    }.merge(lead_block)
  end

  def lead_block
    return { lead: nil, lead_id: nil, thesis_name: nil, advbox_lawsuit_id: nil } if @lead.blank?

    {
      lead: Ramon::DossieService.new(lead: @lead).perform,
      lead_id: @lead.id,
      thesis_name: @lead.thesis&.name,
      advbox_lawsuit_id: @lead.custom_attributes&.dig('advbox', 'lawsuits_id')
    }
  end

  private

  # Rascunho do Copiloto (Captain::Assistant) fica de fora: é sugestão não enviada, viraria eco.
  # Nota do AgentBot fica — é o que o próprio agente já escreveu. IS DISTINCT FROM: where.not
  # descartaria também as mensagens de sender_type NULL (campanha, template).
  def mensagens
    @conversation.messages.includes(:attachments).where.not(message_type: :activity)
                 .where("messages.sender_type IS DISTINCT FROM 'Captain::Assistant'")
                 .reorder(created_at: :desc, id: :desc).limit(LIMITE_MENSAGENS).to_a.reverse.map { |m| mensagem(m) }
  end

  def mensagem(m)
    {
      id: m.id, em: m.created_at.iso8601, de: papel(m), autor: m.sender.try(:name),
      texto: m.content.to_s,
      anexos: m.attachments.map { |a| a.file.attached? ? a.file.filename.to_s : a.file_type }
    }
  end

  def papel(message)
    return 'nota' if message.private?
    return 'lead' if message.incoming?

    message.sender_type == 'User' ? 'atendente' : 'sistema'
  end

  def contato
    return nil if @contact.blank?

    # ponytail: idade não sai daqui — vem pronta em lead[:pessoa][:idade] do DossieService.
    { nome: @contact.name, telefone: @contact.phone_number, email: @contact.email, cpf: @contact.try(:cpf),
      cidade: @contact.additional_attributes&.dig('city'), uf: @contact.additional_attributes&.dig('state') }
  end
end
