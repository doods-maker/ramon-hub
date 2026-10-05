# Avisos internos: sino do hub (lead) e push no celular (ntfy).
module Ramon::Fluxos::Passos::Aviso
  module_function

  def avisar_sino(config, ctx)
    lead = Ramon::Fluxos::Passos::Lead.exigir_lead(ctx)
    texto = ctx.interpolar(config['texto'])
    return { saida: 's', resumo: "faria: sino \"#{texto.truncate(80)}\"" } if ctx.ensaio?

    ids = destinatarios(lead, config)
    return { saida: 's', resumo: 'sino: sem responsável' } if ids.empty?

    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_fluxo_aviso',
                                       meta: { 'label' => texto.truncate(200) }, user_ids: ids).perform
    { saida: 's', resumo: "sino: #{texto.truncate(80)}" }
  end

  # Só gente da conta. Lista vazia nunca chega ao builder: lá ela vira "todo mundo".
  def destinatarios(lead, config)
    (Array(config['user_ids']).map(&:to_i).presence || [(lead.closer || lead.sdr)&.id]).compact & lead.account.account_users.pluck(:user_id)
  end

  def avisar_push(config, ctx)
    titulo = ctx.interpolar(config['titulo'].presence || ctx.execucao.fluxo.nome)
    texto = ctx.interpolar(config['texto'])
    return { saida: 's', resumo: "faria: push \"#{texto.truncate(80)}\"" } if ctx.ensaio?

    Ramon::NtfyPushJob.perform_later(title: titulo, body: texto)
    { saida: 's', resumo: "push: #{texto.truncate(80)}" }
  end
end
