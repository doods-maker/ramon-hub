# Contrato apto (regulamento de remuneração §3; decisão do Eduardo 09/11/2026; plano 2026-11-09-extrato-duas-grades):
# contrato limpo (assinado + documentos mínimos + 7 dias, Ramon::ContratoLimpoJob) → aguarda o jurídico → apto ou
# devolvido com motivo. Sem resposta em 5 dias úteis (seg–sex, sem feriados; conta do dia seguinte e vence no FIM do 5º
# dia, como prazo) o caso fica apto sozinho, na hora do prazo (apto_por_id nil). Depois de apto a comissão é devida:
# cancelar o contrato não tira o apto.
# Só entram na fila os contratos limpos a partir de VALE_DESDE: o estoque anterior não vira "apto por prazo" no 1º deploy.
# Quem valida: o advogado designado no lead → os advogados da tese (Playbooks) → os administradores. O admin sempre pode
# validar. Tese sem advogado fixo (ex.: IR): ao entrar na fila, o responsável do processo no ADVBOX (usuário do hub com o
# mesmo e-mail) vira o designado; o admin troca no painel do lead.
module Ramon::ContratoApto
  DIAS_UTEIS = 5
  ZONA = 'America/Sao_Paulo'.freeze
  AVISO = 'ramon_fluxo_aviso'.freeze
  VALE_DESDE = Time.find_zone(ZONA).local(2026, 11, 10).freeze

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

  # Lista "Aguardando validação": aguardando ou devolvidos que a pessoa pode validar (o admin vê todos).
  # ponytail: filtra em Ruby; SQL se a fila passar de algumas dezenas.
  def fila(account, user)
    account.leads.includes(:thesis, :closer).where(apto_em: nil).where.not(validacao_desde: nil)
           .where(contrato_limpo_em: VALE_DESDE..).order(:validacao_desde)
           .select { |lead| pode_validar?(lead, user) }
  end

  # Valida de uma vez os aguardando que a pessoa pode validar; o resto volta em recusados (sem erro).
  def validar_lote!(account, user, ids)
    leads = account.leads.where(id: ids).to_a
    feitos = leads.select { |lead| situacao(lead) == 'aguardando' && pode_validar?(lead, user) }
    Lead.transaction { feitos.each { |lead| validar!(lead, user) } }
    { validados: feitos.map(&:id), recusados: ids.map(&:to_i) - feitos.map(&:id) }
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

    dia = lead.validacao_desde.in_time_zone(ZONA).to_date
    DIAS_UTEIS.times { dia = proximo_dia_util(dia) }
    Time.find_zone(ZONA).local(dia.year, dia.month, dia.day, 23, 59, 59) # sem fração: o banco guarda microssegundos
  end

  def validar!(lead, user)
    exigir!(lead, user, 'aguardando')
    lead.update!(apto_em: Time.current, apto_por_id: user.id)
    registrar(lead, user, 'apto_validado')
    avisar_closer(lead, "Contrato apto para protocolo: #{lead.name}")
  end

  def devolver!(lead, user, motivo)
    motivo = motivo.to_s.strip
    raise Invalido, 'motivo' if motivo.empty?

    exigir!(lead, user, 'aguardando')
    lead.update!(devolvido_em: Time.current, devolvido_por_id: user.id, devolvido_motivo: motivo)
    registrar(lead, user, 'apto_devolvido', motivo)
    avisar_closer(lead, "Contrato devolvido pelo jurídico: #{lead.name} — #{motivo}")
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
    sem_apto = Lead.where(apto_em: nil).where(contrato_limpo_em: VALE_DESDE..)
    sem_apto.where(validacao_desde: nil).find_each do |lead|
      lead.update!(validacao_desde: lead.contrato_limpo_em, validador_id: lead.validador_id || responsavel_advbox(lead))
      avisar_validadores(lead)
    end
    sem_apto.where(devolvido_em: nil).where.not(validacao_desde: nil).find_each do |lead|
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

  # só para tese sem advogado fixo
  def responsavel_advbox(lead) = (Ramon::ResponsavelAdvbox.usuario_id(lead) if lead.thesis&.validador_ids.blank?)

  def admin?(lead, user) = user.present? && Ramon::Papeis.gestor_ids(lead.account).include?(user.id)

  def dia_util?(dia) = !dia.on_weekend? && !Ramon::Agenda::Feriados.feriado?(dia)

  def proximo_dia_util(dia)
    loop do
      dia += 1
      return dia if dia_util?(dia)
    end
  end

  # Histórico do lead; a devolução também é a base da constância do Programa de Metas (devolvidos no trimestre).
  def registrar(lead, user, kind, valor = nil) = lead.lead_activities.create!(account: lead.account, user: user, kind: kind, to_value: valor)

  def avisar_validadores(lead) = avisar(lead, validadores(lead), "Contrato aguardando validação do jurídico: #{lead.name}")

  def avisar_closer(lead, texto) = avisar(lead, [lead.closer_id].compact, texto)

  def avisar(lead, ids, texto)
    return if ids.empty?

    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: AVISO, user_ids: ids, meta: { 'label' => texto }).perform
  end
end
