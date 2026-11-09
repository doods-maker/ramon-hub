# Contrato apto (regulamento de remuneração §3; decisão do Eduardo 09/11/2026; plano 2026-11-09-extrato-duas-grades):
# contrato limpo (assinado + documentos mínimos + 7 dias, Ramon::ContratoLimpoJob) → aguarda o jurídico → apto ou
# devolvido com motivo. Sem resposta em 5 dias úteis (seg–sex, sem feriados) o caso fica apto sozinho, na hora do prazo
# (apto_por_id nil). Depois de apto a comissão é devida: cancelar o contrato não tira o apto.
# Quem valida: o advogado designado no lead (tese sem advogado fixo, ex.: IR) → os advogados da tese (Playbooks) →
# os administradores. O admin sempre pode validar.
# ponytail: responsável do processo no ADVBOX como validador fica de fora (o processo nasce com usuário fixo).
module Ramon::ContratoApto
  DIAS_UTEIS = 5
  ZONA = 'America/Sao_Paulo'.freeze
  AVISO = 'ramon_fluxo_aviso'.freeze

  class Proibido < StandardError; end
  class Invalido < StandardError; end

  module_function

  def validadores(lead)
    return [lead.validador_id] if lead.validador_id.present?

    da_tese = lead.account.account_users.where(user_id: lead.thesis&.validador_ids.to_a).pluck(:user_id)
    da_tese.presence || Ramon::Papeis.gestor_ids(lead.account)
  end

  def pode_validar?(lead, user)
    user.present? && (admin?(lead, user) || validadores(lead).include?(user.id))
  end

  # aguardando | devolvido | apto | apto_por_prazo | nil (ainda não chegou ao jurídico)
  def situacao(lead)
    return (lead.apto_por_id ? 'apto' : 'apto_por_prazo') if lead.apto_em
    return if lead.validacao_desde.nil? || lead.contrato_limpo_em.nil?

    lead.devolvido_em ? 'devolvido' : 'aguardando'
  end

  # O que o painel e o card leem (vai no comercial_event_data do lead). Quem pode validar vai no jbuilder (depende de quem pede).
  def dados(lead)
    { apto_situacao: situacao(lead), apto_prazo: prazo(lead)&.iso8601, apto_em: lead.apto_em&.iso8601,
      devolvido_motivo: lead.devolvido_motivo, validador_id: lead.validador_id }
  end

  def prazo(lead)
    return unless situacao(lead) == 'aguardando'

    inicio = lead.validacao_desde.in_time_zone(ZONA)
    dia = inicio.to_date
    DIAS_UTEIS.times { dia = proximo_dia_util(dia) }
    inicio.change(year: dia.year, month: dia.month, day: dia.day)
  end

  def validar!(lead, user)
    exigir!(lead, user, 'aguardando')
    lead.update!(apto_em: Time.current, apto_por_id: user.id)
    registrar(lead, user, 'apto_validado')
    avisar_closer(lead, "Contrato apto para protocolo: #{lead.name}")
  end

  def devolver!(lead, user, motivo)
    raise Invalido, 'motivo' if motivo.to_s.strip.empty?

    exigir!(lead, user, 'aguardando')
    lead.update!(devolvido_em: Time.current, devolvido_por_id: user.id, devolvido_motivo: motivo.strip)
    registrar(lead, user, 'apto_devolvido', motivo.strip)
    avisar_closer(lead, "Contrato devolvido pelo jurídico: #{lead.name} — #{motivo.strip}")
  end

  # O Closer do lead (ou o admin) corrigiu: volta para o jurídico com relógio novo.
  def reenviar!(lead, user)
    raise Proibido unless admin?(lead, user) || lead.closer_id == user&.id
    raise Invalido, 'situacao' unless situacao(lead) == 'devolvido'

    lead.update!(validacao_desde: Time.current, devolvido_em: nil, devolvido_por_id: nil, devolvido_motivo: nil)
    registrar(lead, user, 'apto_reenviado')
    avisar_validadores(lead)
  end

  def designar!(lead, user, validador)
    raise Proibido unless admin?(lead, user)

    lead.update!(validador_id: validador&.id)
    avisar_validadores(lead) if validador && situacao(lead) == 'aguardando'
  end

  # Job horário: contrato limpo entra na fila (relógio = carimbo) e o prazo vencido vira apto.
  def rodar!(agora = Time.current)
    Lead.where(validacao_desde: nil, apto_em: nil).where.not(contrato_limpo_em: nil).find_each do |lead|
      lead.update!(validacao_desde: lead.contrato_limpo_em)
      avisar_validadores(lead)
    end
    Lead.where(apto_em: nil, devolvido_em: nil).where.not(validacao_desde: nil).where.not(contrato_limpo_em: nil).find_each do |lead|
      vence = prazo(lead)
      next unless vence && vence <= agora

      lead.update!(apto_em: vence, apto_por_id: nil)
      registrar(lead, nil, 'apto_por_prazo')
      avisar_closer(lead, "Contrato apto por prazo (5 dias úteis sem resposta do jurídico): #{lead.name}")
    end
  end

  def exigir!(lead, user, esperada)
    raise Proibido unless pode_validar?(lead, user)
    raise Invalido, 'situacao' unless situacao(lead) == esperada
  end

  def admin?(lead, user) = user.present? && Ramon::Papeis.gestor_ids(lead.account).include?(user.id)

  def proximo_dia_util(dia)
    loop do
      dia += 1
      return dia unless dia.on_weekend? || Ramon::Agenda::Feriados.feriado?(dia)
    end
  end

  # Histórico do lead; a devolução também é a base da constância do Programa de Metas (devolvidos no trimestre).
  def registrar(lead, user, kind, valor = nil)
    lead.lead_activities.create!(account: lead.account, user: user, kind: kind, to_value: valor)
  end

  def avisar_validadores(lead) = avisar(lead, validadores(lead), "Contrato aguardando validação do jurídico: #{lead.name}")

  def avisar_closer(lead, texto) = avisar(lead, [lead.closer_id].compact, texto)

  def avisar(lead, ids, texto)
    return if ids.empty?

    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: AVISO, user_ids: ids, meta: { 'label' => texto }).perform
  end
end
