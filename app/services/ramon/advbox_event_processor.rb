# Roteia um AdvboxEvent capturado para os fluxos do catálogo (doc
# comercial\docs\2026-07-10-flowter-advbox-plano-integracao.md §4).
#
# O schema do payload do Flowter não é documentado, então a extração é
# defensiva: varre TODAS as strings do payload atrás de nomes de etapa/tarefa
# conhecidos (normalizados sem acento) e TODOS os pares chave→valor atrás de
# CPF/telefone p/ casar com o Contact. Payload sem regra fica 'ignored' e sem
# match fica 'unmatched' — nada se perde, o cru está no AdvboxEvent.
#
# Regra de aprovação: nenhum fluxo fala com o cliente — mensagens viram
# LeadNote "RASCUNHO" e quem envia é o Eduardo.
class Ramon::AdvboxEventProcessor
  # handler → nomes de etapa/tarefa já normalizados (sem acento, upcase);
  # invertido em RULES (nome → handler) na carga da classe.
  RULES = {
    contrato_fechado: ['CONTRATO FECHADO', 'CONTRATO FECHADO / AG. DOCTOS', 'FECHAMENTO COM COBRANCA INICIAIS',
                       'FECHAMENTO COM HONORARIOS RECORRENTES', 'FECHAMENTO SEM COBRANCA INICIAIS'],
    requerimento_protocolado: ['REQUERIMENTO PROTOCOLADO'],
    indeferimento: ['NEGADO / AVISAR CLIENTE'],
    decisao: ['DECISAO PROFERIDA', 'DECISAO DO RECURSO PROFERIDA'],
    exigencia: ['CARTA DE EXIGENCIAS'],
    reativacao_futura: ['BENEFICIO FUTURO / ANOTAR NA AGENDA', 'AGUARDAR - APOSENTADORIA FUTURA', 'CHAMAR - APOSENTADORIA PROXIMA'],
    exito: ['PAGAMENTO RECEBIDO / PAGAR CLIENTE', 'RPV / PRECATORIO EMITIDO'],
    marco: ['SENTENCA PROFERIDA', 'RECURSO JULGADO', 'PERICIA AGENDADA', 'AUDIENCIA / PERICIA REALIZADA',
            'ACAO PROTOCOLADA', 'INICIAL / DEFESA PROTOCOLADA', 'RECURSO PROTOCOLADO',
            'RECURSO ADMINISTRATIVO PROTOCOLADO', 'PROCESSO SOBRESTADO',
            'INFORMAR CLIENTE DO ANDAMENTO DO PROCESSO'],
    concessao: ['BENEFICIO CONCEDIDO / IMPLANTACAO'],
    arquivado: ['ARQUIVADO/ENCERRADO', 'ARQUIVADO POR DESINTERESSE CLIENTE', 'ARQUIVADO POR DETERMINACAO JUDICIAL',
                'ANALISADO E NAO DISTRIBUIDO']
  }.each_with_object({}) { |(handler, names), map| names.each { |name| map[name] = handler } }.freeze

  IDENTITY_PHONE_KEYS = /phone|telefone|celular|fone|whats/i
  IDENTITY_CPF_KEYS = /cpf/i

  def initialize(event)
    @event = event
    @account = event.account
  end

  def perform
    handler, name = detect_rule
    return @event.update!(status: 'ignored', note: 'sem regra p/ os nomes do payload') if handler.blank?

    lead = resolve_lead
    return @event.update!(status: 'unmatched', note: "regra #{name} sem match de contact (CPF/telefone)") if lead.blank?

    send(handler, lead, name)
    @event.update!(status: 'processed', note: "#{name} -> lead ##{lead.id}".truncate(255))
  end

  private

  # -- fluxos ----------------------------------------------------------------

  def contrato_fechado(lead, name)
    won_stage = @account.lead_stages.find_by(is_won: true)
    lead.update!(lead_stage: won_stage) if won_stage && !lead.lead_stage.is_won
    activity(lead, 'advbox_contrato_fechado', "ADVBOX: #{name}")
    notify(lead, 'Contrato fechado no ADVBOX', "#{lead.name}: lead marcado como ganho no hub")
  end

  def requerimento_protocolado(lead, name)
    activity(lead, 'advbox_inss_protocolado', "ADVBOX: #{name} em #{today_br}")
    follow_up(lead, 'Verificar decisão/exigência do INSS (protocolo ADVBOX)', 45.days)
    notify(lead, 'Requerimento protocolado no INSS', "#{lead.name}: follow-up de 45 dias criado")
  end

  def indeferimento(lead, name)
    activity(lead, 'advbox_indeferido', "ADVBOX: #{name}")
    follow_up(lead, 'Avaliar judicialização — INSS negou (ADVBOX)', 1.day)
    draft_note(lead, <<~NOTA)
      RASCUNHO (revisar antes de enviar) — INSS negou:
      "Oi #{first_name(lead)}, tudo bem? Saiu a decisão do INSS sobre o seu pedido e, infelizmente, foi negativa.
      Isso não é o fim: muitos casos como o seu são revertidos na Justiça. Posso te explicar os próximos passos?"
    NOTA
    notify(lead, 'INSS NEGOU - avaliar judicializacao', "#{lead.name}: tarefa na Esteira + rascunho de mensagem no caso")
  end

  def decisao(lead, name)
    activity(lead, 'advbox_decisao', "ADVBOX: #{name}")
    follow_up(lead, 'Analisar decisão registrada no ADVBOX', 2.days)
    notify(lead, 'Decisao proferida (ADVBOX)', "#{lead.name}: analisar e decidir comunicação")
  end

  def exigencia(lead, name)
    activity(lead, 'advbox_exigencia', "ADVBOX: #{name}")
    follow_up(lead, 'Cumprir exigência do INSS — prazo curto (ADVBOX)', 2.days)
    draft_note(lead, <<~NOTA)
      RASCUNHO (revisar antes de enviar) — exigência do INSS:
      "Oi #{first_name(lead)}! O INSS pediu um documento a mais no seu processo. Pode me mandar por aqui quando conseguir? Te ajudo com o que precisar."
    NOTA
    notify(lead, 'Carta de exigencias do INSS', "#{lead.name}: prazo curto — tarefa + rascunho criados")
  end

  def reativacao_futura(lead, name)
    activity(lead, 'advbox_reativacao_futura', "ADVBOX: #{name}")
    follow_up(lead, 'Reativação: benefício futuro — retomar contato', 180.days)
  end

  def exito(lead, name)
    activity(lead, 'advbox_exito', "ADVBOX: #{name}")
    draft_note(lead, <<~NOTA)
      RASCUNHO (revisar antes de enviar) — comunicado de êxito:
      "#{first_name(lead)}, ótima notícia! 🎉 Saiu o pagamento do seu processo. Foi uma alegria acompanhar seu caso até aqui.
      Se puder, sua avaliação no Google ajuda muito outras pessoas a nos encontrarem."
    NOTA
    notify(lead, 'Exito: pagamento no ADVBOX', "#{lead.name}: rascunho de comunicado pronto no caso")
  end

  def concessao(lead, name)
    activity(lead, 'advbox_concessao', "ADVBOX: #{name}")
    draft_note(lead, <<~NOTA)
      RASCUNHO (revisar antes de enviar) — benefício concedido:
      "#{first_name(lead)}, notícia boa! 🎉 O INSS CONCEDEU o seu benefício. Agora vamos conferir a implantação e os valores — te aviso de cada passo."
    NOTA
    notify(lead, 'Beneficio CONCEDIDO (ADVBOX)', "#{lead.name}: rascunho de boa notícia pronto no caso")
  end

  def marco(lead, name)
    activity(lead, 'advbox_marco', "ADVBOX: #{name}")
    notify(lead, 'Marco processual (ADVBOX)', "#{lead.name}: #{name}")
  end

  def arquivado(lead, name)
    lead.lead_tasks.open_tasks.update_all(completed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    activity(lead, 'advbox_arquivado', "ADVBOX: #{name} — follow-ups do hub encerrados")
  end

  # -- extração defensiva ----------------------------------------------------

  def detect_rule
    each_string(@event.payload) do |raw|
      name = normalize(raw)
      return [RULES[name], name] if RULES.key?(name)
    end
    nil
  end

  def resolve_lead
    contact = contact_by_cpf || contact_by_phone
    return if contact.blank?

    @account.leads.open.find_by(contact_id: contact.id) ||
      @account.leads.funil.where(contact_id: contact.id).reorder(created_at: :desc).first
  end

  def contact_by_cpf
    cpf = first_value_for(IDENTITY_CPF_KEYS)&.gsub(/\D/, '')
    @account.contacts.find_by(cpf: cpf) if cpf&.length == 11
  end

  def contact_by_phone
    phone = normalize_phone(first_value_for(IDENTITY_PHONE_KEYS))
    @account.contacts.find_by(phone_number: phone) if phone
  end

  def first_value_for(key_pattern, obj = @event.payload)
    case obj
    when Hash then hash_value_for(key_pattern, obj)
    when Array then obj.lazy.filter_map { |item| first_value_for(key_pattern, item) }.first
    end
  end

  def hash_value_for(key_pattern, hash)
    hash.each do |key, value|
      return value.to_s if identity_leaf?(key_pattern, key, value)

      found = first_value_for(key_pattern, value)
      return found if found
    end
    nil
  end

  def identity_leaf?(key_pattern, key, value)
    key.to_s.match?(key_pattern) && value.present? && !value.is_a?(Enumerable)
  end

  def each_string(obj, &)
    case obj
    when String then yield(obj)
    when Hash then obj.each_value { |value| each_string(value, &) }
    when Array then obj.each { |item| each_string(item, &) }
    end
  end

  def normalize(raw)
    I18n.transliterate(raw.to_s).upcase.squish
  end

  # mesma régua do Cal.com/import: BR de 10-11 dígitos vira +55
  def normalize_phone(raw)
    digits = raw.to_s.gsub(/\D/, '')
    return "+#{digits}" if [12, 13].include?(digits.length) && digits.start_with?('55')
    return "+55#{digits}" if [10, 11].include?(digits.length)

    nil
  end

  # -- efeitos ---------------------------------------------------------------

  def activity(lead, kind, text)
    lead.lead_activities.create!(account: @account, kind: kind, to_value: text.truncate(255))
  end

  def follow_up(lead, title, due_in)
    lead.lead_tasks.create!(account: @account, kind: 'follow_up', title: title.truncate(255), due_at: due_in.from_now)
  end

  def draft_note(lead, body)
    lead.lead_notes.create!(account: @account, body: body.strip.truncate(1000))
  end

  def notify(lead, title, body)
    return if ENV.fetch('NTFY_TOPIC', nil).blank?

    Ramon::NtfyPushJob.perform_later(lead.id, title: title, body: body)
  end

  def first_name(lead)
    lead.name.to_s.split.first.presence || 'cliente'
  end

  def today_br
    Time.zone.today.strftime('%d/%m/%Y')
  end
end
