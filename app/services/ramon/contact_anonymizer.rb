# Anonimização LGPD do titular (art. 16): zera os dados pessoais do contato e
# redige PII remanescente em mensagens e notas via Ramon::Pseudonymizer,
# preservando conversas e estatísticas (anonimização, não apagamento físico).
# Usado pelo delete da UI (ContactsController#destroy); fluxos internos que
# exigem destroy físico (ex.: merge de contatos duplicados) seguem intocados.
class Ramon::ContactAnonymizer
  # A trilha (audits) é somente-inclusão e fica: o Registro de ações continua
  # mostrando quem editou/anonimizou e quando. Os VALORES antigos de PII em
  # audited_changes viram '[anonimizado]' — no contato e no(s) contato(s)
  # mesclado(s) nele (1 nível; ver Ramon::ContactMergePessoa). É a única
  # escrita que o trigger audits_somente_inclusao aceita: a flag vale só nesta
  # transação e só audited_changes pode mudar. `blocked` não é PII e fica.
  REDACAO_AUDITS_SQL = <<~SQL.squish.freeze
    SELECT set_config('ramon.redacao_lgpd', 'on', true);
    UPDATE audits SET audited_changes = (
      SELECT jsonb_object_agg(chave, CASE
        WHEN chave = 'blocked' THEN valor
        WHEN jsonb_typeof(valor) = 'array' THEN '["[anonimizado]", "[anonimizado]"]'::jsonb
        ELSE '"[anonimizado]"'::jsonb END)
      FROM jsonb_each(audited_changes) AS par(chave, valor))
    WHERE auditable_type = 'Contact' AND audited_changes <> '{}'::jsonb
      AND (auditable_id = :id OR auditable_id IN (
        SELECT mesclado.auditable_id FROM audits mesclado
        WHERE mesclado.auditable_type = 'Contact' AND mesclado.action = 'destroy' AND mesclado.comment = :mesclado));
    SELECT set_config('ramon.redacao_lgpd', 'off', true);
  SQL

  # comentario: vai no audit da anonimização (a tela diferencia a exclusão em massa).
  def initialize(contact, comentario: 'anonimizado')
    @contact = contact
    @comentario = comentario
  end

  def perform
    redact_messages
    redact_notes
    @contact.avatar.purge if @contact.avatar.attached?
    anonymize_contact
    redact_audits
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
      audit_comment: @comentario,
      name: "Titular anonimizado ##{@contact.id}",
      middle_name: '', last_name: '',
      email: nil, phone_number: nil, identifier: nil,
      cpf: nil, data_nascimento: nil, sexo: nil,
      location: '', country_code: '',
      additional_attributes: {}, custom_attributes: {}
    )
  end

  def redact_audits
    sql = ActiveRecord::Base.sanitize_sql([REDACAO_AUDITS_SQL, { id: @contact.id, mesclado: "mesclado:#{@contact.id}" }])
    ActiveRecord::Base.connection.execute(sql)
  end
end
