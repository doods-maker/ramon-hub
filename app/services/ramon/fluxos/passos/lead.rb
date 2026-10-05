# Passos que mexem no lead (funil e Esteira).
module Ramon::Fluxos::Passos::Lead
  module_function

  def mover_etapa(config, ctx)
    lead = exigir_lead(ctx)
    etapa = lead.account.lead_stages.find(config['etapa_id'])
    return { saida: 's', resumo: "faria: mover para #{etapa.name}" } if ctx.ensaio?

    lead.update!(lead_stage: etapa)
    # a mudança feita pelo próprio fluxo não pode cancelá-lo na próxima espera
    ctx.execucao.contexto = ctx.execucao.contexto.merge('etapa_inicial_id' => etapa.id)
    { saida: 's', resumo: "moveu para #{etapa.name}" }
  end

  def criar_tarefa(config, ctx)
    lead = exigir_lead(ctx)
    titulo = ctx.interpolar(config['titulo']).truncate(255)
    prazo = (Time.find_zone!(Fluxo::ZONA).now + config.fetch('prazo_dias', 1).to_i.days).end_of_day
    return { saida: 's', resumo: "faria: tarefa \"#{titulo}\"" } if ctx.ensaio?

    responsavel = responsavel_da_tarefa(lead, config)
    lead.lead_tasks.create!(account: lead.account, kind: kind_da_tarefa(config), title: titulo, due_at: prazo, user: responsavel)
    { saida: 's', resumo: "tarefa \"#{titulo}\" · #{responsavel&.name || 'sem responsável'}" }
  end

  def responsavel_da_tarefa(lead, config)
    config['responsavel_id'].present? ? lead.account.users.find(config['responsavel_id']) : (lead.closer || lead.sdr)
  end

  def kind_da_tarefa(config)
    LeadTask::KINDS.include?(config['tipo']) ? config['tipo'] : 'other'
  end

  def exigir_lead(ctx)
    ctx.lead || raise(Ramon::Fluxos::PassoImpossivel, 'este passo precisa de um lead')
  end
end
