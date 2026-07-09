# Anonimização LGPD do titular (art. 16): zera os dados pessoais do contato e
# redige PII remanescente em mensagens e notas via Ramon::Pseudonymizer,
# preservando conversas e estatísticas (anonimização, não apagamento físico).
# Usado pelo delete da UI (ContactsController#destroy); fluxos internos que
# exigem destroy físico (ex.: merge de contatos duplicados) seguem intocados.
class Ramon::ContactAnonymizer
  def initialize(contact)
    @contact = contact
  end

  def perform
    redact_messages
    redact_notes
    @contact.avatar.purge if @contact.avatar.attached?
    anonymize_contact
    purge_audits
    @contact
  end

  private

  def name_tokens
    @name_tokens ||= [@contact.name, @contact.middle_name, @contact.last_name]
  end

  # Redige TODAS as mensagens das conversas do titular (PII aparece também em
  # respostas de agente que citam CPF/telefone). update_columns de propósito:
  # redação em massa, sem callbacks/broadcasts/reindex.
  # rubocop:disable Rails/SkipsModelValidations
  def redact_messages
    Message.where(conversation_id: @contact.conversations.select(:id)).find_each do |message|
      next if message.content.blank?

      masked = Ramon::Pseudonymizer.mask(message.content, names: name_tokens)
      message.update_columns(content: masked) if masked != message.content
    end
  end

  def redact_notes
    @contact.notes.find_each do |note|
      masked = Ramon::Pseudonymizer.mask(note.content, names: name_tokens)
      note.update_columns(content: masked) if masked != note.content
    end
  end
  # rubocop:enable Rails/SkipsModelValidations

  def anonymize_contact
    @contact.update!(
      name: "Titular anonimizado ##{@contact.id}",
      middle_name: '', last_name: '',
      email: nil, phone_number: nil, identifier: nil,
      cpf: nil, data_nascimento: nil, sexo: nil,
      location: '', country_code: '',
      additional_attributes: {}, custom_attributes: {}
    )
  end

  # A trilha do audited guarda os valores antigos (audited_changes) — manter
  # seria desfazer a anonimização; o histórico de auditoria sai junto com a PII.
  def purge_audits
    Audited.audit_class.where(auditable: @contact).delete_all
  end
end
