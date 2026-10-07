# Avisos internos: sino do hub (lead) e push no celular (ntfy).
module Ramon::Fluxos::Passos::Aviso
  # Quem recebe por papel. B4.1: 'closer_e_sdr' = a regra do lembrete de reunião; 'conta' = todo mundo (reunião
  # marcada/cancelada). B4.2: 'sdr_ou_gestores' / 'gestores' = o SLA da 1ª resposta (Ramon::Papeis.gestor_ids).
  PARA = {
    'closer_e_sdr' => ->(lead) { Ramon::Fluxos::Reunioes.destinatarios(lead) },
    'conta' => ->(lead) { lead.account.account_users.pluck(:user_id) },
    'sdr_ou_gestores' => ->(lead) { lead.sdr_id ? [lead.sdr_id] : Ramon::Papeis.gestor_ids(lead.account) },
    'gestores' => ->(lead) { Ramon::Papeis.gestor_ids(lead.account) }
  }.freeze

  module_function

  def avisar_sino(config, ctx)
    lead = Ramon::Fluxos::Passos::Lead.exigir_lead(ctx)
    texto = ctx.interpolar(config['texto'])
    ids = destinatarios(lead, config)
    return { saida: 's', resumo: "faria: sino para #{nomes(ids)}: \"#{texto.truncate(80)}\"" } if ctx.ensaio?
    return { saida: 's', resumo: 'sino: sem responsável' } if ids.empty?

    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_fluxo_aviso',
                                       meta: { 'label' => texto.truncate(200) }, user_ids: ids).perform
    { saida: 's', resumo: "sino: #{texto.truncate(80)}" }
  end

  # Só gente da conta. Lista vazia nunca chega ao builder: lá ela vira "todo mundo".
  def destinatarios(lead, config)
    regra = PARA[config['para']]
    ids = regra ? regra.call(lead) : Array(config['user_ids']).map(&:to_i).presence || [(lead.closer || lead.sdr)&.id]
    ids.compact & lead.account.account_users.pluck(:user_id)
  end

  # Ordem alfabética: a comparação da B4.1 (Ramon::Fluxos::CompararLembretes::PESSOAS) lê este texto.
  def nomes(ids) = User.where(id: ids).order(:name).pluck(:name).join(', ').presence || 'ninguém (sem responsável)'

  def avisar_push(config, ctx)
    titulo = ctx.interpolar(config['titulo'].presence || ctx.execucao.fluxo.nome)
    texto = ctx.interpolar(config['texto'])
    return { saida: 's', resumo: "faria: push \"#{texto.truncate(80)}\"" } if ctx.ensaio?

    pulo = pular_push(config, ctx)
    return pulo if pulo

    Ramon::NtfyPushJob.perform_later(title: titulo, body: texto)
    { saida: 's', resumo: "push: #{texto.truncate(80)}" }
  end

  # B4.3: "uma vez por dia" (a cadência do código mandava 1 push por lote): só a 1ª execução do fluxo no dia (fuso SP) avisa.
  # O botão "Preparar retomada" (gatilho 'botao') não avisa nem gasta o aviso do dia — o código não avisava no botão.
  # sem_balao: o executor não põe na conversa (até 14 balões/dia de "já saiu" no lote da cadência).
  def pular_push(config, ctx)
    return unless config['uma_vez_por_dia']
    return { saida: 's', resumo: 'push: só no lote do dia', sem_balao: true } if ctx.gatilho('botao')

    { saida: 's', resumo: 'push: já saiu hoje (1 por dia)', sem_balao: true } unless primeiro_do_dia?(ctx)
  end

  def primeiro_do_dia?(ctx)
    chave = "RAMON::FLUXO_PUSH::#{ctx.execucao.fluxo_id}::#{Time.find_zone!(Fluxo::ZONA).today}"
    Redis::Alfred.set(chave, '1', nx: true, ex: 2.days.to_i)
  end
end
