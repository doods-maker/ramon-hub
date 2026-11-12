# Anonimização LGPD do titular (art. 16): zera os dados pessoais do contato e
# redige PII remanescente em mensagens e notas via Ramon::Pseudonymizer,
# preservando conversas e estatísticas (anonimização, não apagamento físico).
# Usado pelo delete da UI (ContactsController#destroy); fluxos internos que
# exigem destroy físico (ex.: merge de contatos duplicados) seguem intocados.
# Titular que é cliente (decisão de 11/11/2026): nada é apagado nem mascarado. O pedido fica no histórico do lead,
# os gestores recebem o sino e `perform` levanta ClienteGanho; eliminar passa a ser decisão manual da gestão.
# Quem não é cliente (decisões de 12/11/2026): tudo numa transação, inclusive o que ficou nos leads e nas conversas
# (Ramon::RastrosDoTitular); a pasta do Drive do lead vai para a lixeira depois do commit, registrada no histórico do lead.
class Ramon::ContactAnonymizer
  class ClienteGanho < StandardError; end

  PEDIDO = 'eliminacao_pedida'.freeze
  DRIVE_LIXEIRA = 'drive_lixeira'.freeze
  DRIVE_FALHOU = 'drive_lixeira_falhou'.freeze

  # A trilha (audits) é somente-inclusão e fica: o Registro de ações continua
  # mostrando quem editou/anonimizou e quando. Os VALORES antigos de PII em
  # audited_changes viram '[anonimizado]' — no contato e no(s) contato(s)
  # mesclado(s) nele (1 nível; ver Ramon::ContactMergePessoa). É a única
  # escrita que o trigger audits_somente_inclusao aceita: a flag vale só nesta
  # transação e só audited_changes pode mudar. `blocked` não é PII e fica.
  # Lead (não cliente) do titular: só os motivos escritos à mão; etapa, datas, valor e responsáveis ficam (estatística).
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
    UPDATE audits SET audited_changes = (
      SELECT jsonb_object_agg(chave, CASE
        WHEN chave NOT IN ('lost_reason', 'devolvido_motivo') THEN valor
        WHEN jsonb_typeof(valor) = 'array' THEN '["[anonimizado]", "[anonimizado]"]'::jsonb
        ELSE '"[anonimizado]"'::jsonb END)
      FROM jsonb_each(audited_changes) AS par(chave, valor))
    WHERE auditable_type = 'Lead' AND auditable_id IN (:leads)
      AND jsonb_exists_any(audited_changes, ARRAY['lost_reason', 'devolvido_motivo']);
    SELECT set_config('ramon.redacao_lgpd', 'off', true);
  SQL

  # comentario: vai no audit da anonimização (a tela diferencia a exclusão em massa).
  def initialize(contact, comentario: 'anonimizado')
    @contact = contact
    @comentario = comentario
  end

  # A recusa grava o pedido antes, fora da transação. Arquivo (avatar, áudio) e Drive só depois: não voltam com rollback.
  # ponytail: requires_new vira savepoint se o chamador abrir transação, e aí o Drive vai antes do commit de fora;
  # hoje nenhum chamador (ContactsController#destroy, BulkDeleteService) abre.
  def perform
    recusar_cliente!
    leads = leads_do_titular.to_a
    name_tokens # antes da transação: os leads ainda têm o nome
    rastros = Ramon::RastrosDoTitular.new(@contact, leads, ->(texto) { mascarar(texto) })
    ActiveRecord::Base.transaction(requires_new: true) do
      redact_messages
      redact_notes
      rastros.perform
      anonymize_contact
      redact_audits(leads)
    end
    @contact.avatar.purge_later if @contact.avatar.attached?
    rastros.audios.each(&:purge_later)
    lixeira_do_drive(rastros.pastas_drive)
    @contact
  end

  private

  # Sair da etapa de ganho zera won_at: apto_em e contrato_cancelado_em guardam que o contrato existiu.
  CLIENTE_SQL = 'leads.won_at IS NOT NULL OR leads.apto_em IS NOT NULL OR leads.contrato_cancelado_em IS NOT NULL OR leads.source = ?'.freeze

  # Cliente = lead ganho (hoje ou antes de cancelar) ou caso de cálculo, ligado pelo contato OU por uma conversa dele
  # (caso de cálculo nasce sem contact_id: olhar só @contact.leads deixaria o cliente sem proteção).
  def leads_de_cliente = leads_ligados(@contact.account.leads).where(CLIENTE_SQL, Lead::FONTE_CALCULO)

  def leads_ligados(leads) = leads.where(contact_id: @contact.id).or(leads.where(conversation_id: @contact.conversations.select(:id)))

  # O que é anonimizado: lead pela conversa só se não for de outro contato.
  def leads_do_titular = leads_ligados(@contact.account.leads.where(contact_id: [nil, @contact.id]))

  # Antes de qualquer escrita. Sino só no hub (pode levar o nome do lead); sem push ntfy.
  # O registro vai no lead do funil quando há um; caso de cálculo só na falta dele.
  def recusar_cliente!
    lead = leads_de_cliente.funil.reorder(:id).last || leads_de_cliente.reorder(:id).last # reorder: Lead tem ordem padrão
    # Petição é caso na Justiça: cliente, mesmo sem lead ganho. Sem lead não há onde registrar; a tela avisa do mesmo jeito.
    raise ClienteGanho if lead.nil? && Peticao.exists?(account_id: @contact.account_id, contact_id: @contact.id)
    return if lead.nil?

    Ramon::ContratoApto.registrar(lead, autor, PEDIDO)
    Ramon::ContratoApto.avisar(lead, Ramon::Papeis.gestor_ids(lead.account),
                               "Pedido de eliminação de dados de cliente com contrato: #{lead.name}. Nada foi apagado.")
    raise ClienteGanho
  end

  # O nome do lead pode diferir do contato (digitado pela equipe, vindo do ADVBOX): entra na máscara também.
  def name_tokens
    @name_tokens ||= [@contact.name, @contact.middle_name, @contact.last_name, *leads_do_titular.pluck(:name)]
  end

  def mascarar(texto) = texto.blank? ? texto : Ramon::Pseudonymizer.mask(texto, names: name_tokens)

  # Redige TODAS as mensagens das conversas do titular (PII aparece também em
  # respostas de agente que citam CPF/telefone). update_columns de propósito:
  # redação em massa, sem callbacks/broadcasts/reindex.
  # rubocop:disable Rails/SkipsModelValidations
  def redact_messages
    Message.where(conversation_id: @contact.conversations.select(:id)).find_each do |message|
      next if message.content.blank? && message.processed_message_content.blank?

      novos = { content: mascarar(message.content), processed_message_content: mascarar(message.processed_message_content) }
      message.update_columns(novos) if novos.any? { |coluna, valor| message[coluna] != valor }
    end
  end

  def redact_notes
    @contact.notes.find_each do |note|
      masked = mascarar(note.content)
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

  # Falha no Drive não desfaz a eliminação: fica no histórico do lead para apagar à mão (o id da pasta vai junto).
  def lixeira_do_drive(pastas)
    pastas.each do |pasta, lead|
      Ramon::DriveClient.lixeira(pasta)
      Ramon::ContratoApto.registrar(lead, autor, DRIVE_LIXEIRA)
    rescue StandardError => e
      Rails.logger.warn("[lgpd] pasta #{pasta} do lead #{lead.id} não foi para a lixeira: #{e.class} #{e.message}")
      Ramon::ContratoApto.registrar(lead, autor, DRIVE_FALHOU, pasta)
    end
  end

  def autor = Audited.store[:audited_user] || Current.user

  def redact_audits(leads)
    sql = ActiveRecord::Base.sanitize_sql([REDACAO_AUDITS_SQL, { id: @contact.id, mesclado: "mesclado:#{@contact.id}", leads: leads.map(&:id) }])
    ActiveRecord::Base.connection.execute(sql)
  end
end
