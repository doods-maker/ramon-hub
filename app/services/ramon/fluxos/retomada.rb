# B4.3 (spec §8): a cadência de retomada (W4) saindo do código para um fluxo, direto (sem sombra). As regras da retomada
# moram aqui, uma vez só, e valem para os dois lados — o código (Ramon::FollowUpDraftService, o botão "Preparar retomada")
# e o fluxo (gatilho "Lead parado" com retomada + passo "Registrar a retomada"). A chave e a semeadura são da migração
# genérica (Ramon::Fluxos::Migracao, grupo 'cadencia').
module Ramon::Fluxos::Retomada
  TETO = 15 # retomadas por dia por conta (o limite do dia com que o fluxo nasce)
  INTERVALO_DIAS = 5 # entre uma retomada e a próxima do mesmo lead
  GRUPO = 'cadencia'.freeze # a migração (Ramon::Fluxos::Migracao::GRUPOS) e o sistema_chave do fluxo

  module_function

  # Por que o lead NÃO pode receber retomada agora (nil = pode) — o painel explica o motivo (422 do follow_up_draft).
  def motivo(lead)
    return { reason: 'no_conversation' } if lead.conversation_id.blank?
    return { reason: 'open_follow_up' } if lead.lead_tasks.open_tasks.exists?(kind: 'follow_up')

    ultima = ultima_em(lead)
    return if ultima.nil? || ultima <= INTERVALO_DIAS.days.ago

    { reason: 'recent_follow_up', last_at: ultima.iso8601,
      days_ago: (Time.zone.today - ultima.to_date).to_i, min_gap_days: INTERVALO_DIAS }
  end

  # Data venenosa (a API grava qualquer coisa no jsonb) → nil, tratada como "nunca".
  def ultima_em(lead)
    valor = contador(lead)['ultima_em']
    return if valor.blank?

    Time.zone.parse(valor.to_s)
  rescue ArgumentError
    nil
  end

  # A próxima retomada do lead (as contadas + 1).
  def tentativa(lead) = contador(lead)['tentativas'].to_i + 1

  # O contador follow_up do lead; não-Hash (string/array gravado pela API) conta como vazio — não derruba o lote.
  def contador(lead)
    valor = lead.custom_attributes['follow_up']
    valor.is_a?(Hash) ? valor : {}
  end
  private_class_method :contador

  def dias_parado(lead) = lead.stage_entered_at.blank? ? 0 : (Time.zone.today - lead.stage_entered_at.to_date).to_i

  # Conta a retomada (o contador do card, do banner e do Watchdog). Lição lost update: relê e escreve SÓ a chave follow_up.
  def registrar!(lead)
    lead.reload
    numero = tentativa(lead)
    follow_up = { 'tentativas' => numero, 'ultima_em' => Time.current.iso8601 }
    lead.update!(custom_attributes: lead.custom_attributes.merge('follow_up' => follow_up))
    numero
  end

  # Só o fluxo da cadência (o Migracao.migrado? genérico pegaria os das outras migrações).
  def migrado?(fluxo) = fluxo.origem == 'usuario' && fluxo.sistema_chave == GRUPO
end
