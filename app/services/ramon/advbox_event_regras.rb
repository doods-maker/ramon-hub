# Os efeitos de cada regra do ADVBOX como o código sempre fez — saíram do Ramon::AdvboxEventProcessor na B4.5 sem mudar
# nada. Quem chama é Ramon::Fluxos::EventosAdvbox: quando o fluxo "Eventos do ADVBOX" não está no comando, ou não pegou
# o evento. Sai na limpeza (E7), junto com o JSON sistema/eventos_advbox.json.
#
# Regra de aprovação: nenhum fluxo fala com o cliente — mensagens viram LeadNote "RASCUNHO" e quem envia é o Eduardo.
class Ramon::AdvboxEventRegras
  def initialize(account)
    @account = account
  end

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
    nps_draft(lead)
    notify(lead, 'Exito: pagamento no ADVBOX', "#{lead.name}: rascunho de comunicado pronto no caso")
  end

  def concessao(lead, name)
    activity(lead, 'advbox_concessao', "ADVBOX: #{name}")
    draft_note(lead, <<~NOTA)
      RASCUNHO (revisar antes de enviar) — benefício concedido:
      "#{first_name(lead)}, notícia boa! 🎉 O INSS CONCEDEU o seu benefício. Agora vamos conferir a implantação e os valores — te aviso de cada passo."
    NOTA
    nps_draft(lead)
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

  private

  def activity(lead, kind, text)
    lead.lead_activities.create!(account: @account, kind: kind, to_value: text.truncate(255))
  end

  def follow_up(lead, title, due_in)
    lead.lead_tasks.create!(account: @account, kind: 'follow_up', title: title.truncate(255), due_at: due_in.from_now)
  end

  def draft_note(lead, body)
    lead.lead_notes.create!(account: @account, body: body.strip.truncate(1000))
  end

  # Pesquisa NPS da fase de êxito — o guard nps.pedido_exito_em (dentro do job)
  # garante que a fase pede uma vez só.
  def nps_draft(lead)
    Ramon::NpsDraftJob.perform_later(lead.id, fase: 'exito')
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
