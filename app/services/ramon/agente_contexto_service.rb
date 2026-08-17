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
      contato: contato,
      lead: (@lead ? Ramon::DossieService.new(lead: @lead).perform : nil),
      lead_id: @lead&.id,
      thesis_name: @lead&.thesis&.name,
      advbox_lawsuit_id: @lead&.custom_attributes&.dig('advbox', 'lawsuits_id')
    }
  end

  private

  def mensagens
    @conversation.messages.where.not(message_type: :activity).reorder(created_at: :desc).limit(LIMITE_MENSAGENS).to_a.reverse.map do |m|
      {
        id: m.id, em: m.created_at.iso8601, de: papel(m), autor: m.sender.try(:name),
        texto: m.content.to_s,
        anexos: m.attachments.map { |a| a.file.attached? ? a.file.filename.to_s : a.file_type }
      }
    end
  end

  def papel(message)
    return 'nota' if message.private?
    return 'lead' if message.incoming?

    message.sender_type == 'User' ? 'atendente' : 'sistema'
  end

  def contato
    return nil if @contact.blank?

    { nome: @contact.name, telefone: @contact.phone_number, email: @contact.email, cpf: @contact.try(:cpf),
      cidade: @contact.additional_attributes&.dig('city'), uf: @contact.additional_attributes&.dig('state'), idade: idade }
  end

  def idade
    born = @contact.try(:data_nascimento)
    return nil if born.blank?

    (Time.zone.today.strftime('%Y%m%d').to_i - born.strftime('%Y%m%d').to_i) / 10_000
  end
end
