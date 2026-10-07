# Roteia um AdvboxEvent capturado para os fluxos do catálogo (doc
# comercial\docs\2026-07-10-flowter-advbox-plano-integracao.md §4).
#
# O schema do payload do Flowter não é documentado, então a extração é
# defensiva: varre TODAS as strings do payload atrás de nomes de etapa/tarefa
# conhecidos (normalizados sem acento) e TODOS os pares chave→valor atrás de
# CPF/telefone p/ casar com o Contact. Payload sem regra fica 'ignored' e sem
# match fica 'unmatched' — nada se perde, o cru está no AdvboxEvent.
#
# Os efeitos de cada regra: Ramon::AdvboxEventRegras (código) ou o fluxo "Eventos do ADVBOX" — quem decide, uma vez por
# evento, é Ramon::Fluxos::EventosAdvbox (B4.5).
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
    marco: ['SENTENCA PROFERIDA', 'RECURSO JULGADO', 'PERICIA AGENDADA', 'AUDIENCIA / PERICIA REALIZADA', 'ACAO PROTOCOLADA',
            'INICIAL / DEFESA PROTOCOLADA', 'RECURSO PROTOCOLADO', 'RECURSO ADMINISTRATIVO PROTOCOLADO', 'PROCESSO SOBRESTADO',
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

    Ramon::Fluxos::EventosAdvbox.processar(lead, handler.to_s, name)
    @event.update!(status: 'processed', note: "#{name} -> lead ##{lead.id}".truncate(255))
  end

  private

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
end
