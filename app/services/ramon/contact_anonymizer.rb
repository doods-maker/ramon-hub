# Anonimização LGPD do titular (art. 16): zera os dados pessoais do contato e
# redige PII remanescente em mensagens e notas via Ramon::Pseudonymizer,
# preservando conversas e estatísticas (anonimização, não apagamento físico).
# Usado pelo delete da UI (ContactsController#destroy); fluxos internos que
# exigem destroy físico (ex.: merge de contatos duplicados) seguem intocados.
#
# Alcança também o que o titular deixou fora do contato: os leads dele (nome,
# CNIS, dados de contrato, link mágico, notas, reuniões, cálculos, triagens),
# os anexos das conversas e o telefone em contact_inboxes.source_id.
# Caso de cliente (lead ganho ou caso de cálculo vindo do ADVBOX) NÃO é
# redigido: não há regra escrita sobre o dever de guarda, então dele só morre o
# link mágico, e os anexos das conversas ficam (são os documentos do caso).
# Drive, ADVBOX e a conta do Painel do Cliente ficam fora (decisão do dono).
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
    anonymize_leads
    purge_attachments
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

  def anonymize_leads
    leads.each do |lead|
      next lead.update_columns(portal_token: nil) if caso_de_cliente?(lead)

      redact_lead_records(lead)
      lead.update_columns(name: "Titular anonimizado ##{@contact.id}", cnis: nil, custom_attributes: {},
                          portal_token: nil, devolvido_motivo: nil)
    end
  end

  # Notas e reuniões: mascaradas como as mensagens (o registro fica). Cálculo (CNIS inteiro no snapshot) e sugestão
  # do copiloto (rascunho de mensagem) não têm o que preservar: saem. Triagem fica só com status e contagem de tokens.
  def redact_lead_records(lead)
    lead.lead_notes.each { |nota| nota.update_columns(body: mask(nota.body)) }
    lead.reunioes.each { |reuniao| redact_reuniao(reuniao) }
    lead.calculos.delete_all
    lead.copilot_suggestions.delete_all
    lead.lead_triages.update_all(source_text: nil, result: nil, kit: nil)
    lead.lead_activities.where(kind: 'note_added').update_all(to_value: nil)
  end

  def redact_reuniao(reuniao)
    reuniao.audio.purge if reuniao.audio.attached?
    reuniao.update_columns(titulo: mask(reuniao.titulo), transcricao: mask(reuniao.transcricao), ata: mask(reuniao.ata))
  end

  # O telefone também mora no source_id (WhatsApp); trocado, mensagem nova do mesmo número não cai no titular anonimizado.
  def anonymize_contact_inboxes
    @contact.contact_inboxes.each { |ci| ci.update_columns(source_id: "anonimizado-#{ci.id}") }
  end
  # rubocop:enable Rails/SkipsModelValidations

  def leads
    @leads ||= @contact.leads.to_a
  end

  def caso_de_cliente?(lead) = lead.won_at.present? || lead.source == Lead::FONTE_CALCULO

  def mask(texto) = texto.presence && Ramon::Pseudonymizer.mask(texto, names: name_tokens)

  # Anexos das conversas (RG, laudo, áudio transcrito): o arquivo sai do storage junto com a linha.
  def purge_attachments
    return if leads.any? { |lead| caso_de_cliente?(lead) }

    Attachment.where(message_id: Message.where(conversation_id: @contact.conversations.select(:id)).select(:id)).find_each(&:destroy!)
  end

  def anonymize_contact
    anonymize_contact_inboxes
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
