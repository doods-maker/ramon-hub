# Avisos internos: sino do hub (lead) e push no celular (ntfy).
module Ramon::Fluxos::Passos::Aviso
  module_function

  def avisar_sino(config, ctx)
    lead = Ramon::Fluxos::Passos::Lead.exigir_lead(ctx)
    texto = ctx.interpolar(config['texto'])
    ids = Array(config['user_ids']).presence || [(lead.closer || lead.sdr)&.id].compact
    return { saida: 's', resumo: "faria: sino \"#{texto.truncate(80)}\"" } if ctx.ensaio?

    Ramon::LeadNotificationBuilder.new(lead: lead, notification_type: 'ramon_fluxo_aviso',
                                       meta: { 'label' => texto.truncate(200) }, user_ids: ids.presence).perform
    { saida: 's', resumo: "sino: #{texto.truncate(80)}" }
  end

  def avisar_push(config, ctx)
    titulo = ctx.interpolar(config['titulo'].presence || ctx.execucao.fluxo.nome)
    texto = ctx.interpolar(config['texto'])
    return { saida: 's', resumo: "faria: push \"#{texto.truncate(80)}\"" } if ctx.ensaio?

    Ramon::NtfyPushJob.perform_later(title: titulo, body: texto)
    { saida: 's', resumo: "push: #{texto.truncate(80)}" }
  end
end
