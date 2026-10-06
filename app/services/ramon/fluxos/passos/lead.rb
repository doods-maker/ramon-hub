# Passos que mexem no lead (funil e Esteira).
module Ramon::Fluxos::Passos::Lead
  module_function

  def mover_etapa(config, ctx)
    lead = exigir_lead(ctx)
    etapa = lead.account.lead_stages.find(config['etapa_id'])
    # B4.1: "só para a frente" (como a reunião marcada do código): quem já está adiante fica onde está
    if config['so_para_frente'] && lead.lead_stage.position >= etapa.position
      return { saida: 's', resumo: "etapa: já está em #{lead.lead_stage.name} (só para a frente)" }
    end
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

  def registrar_atividade(config, ctx)
    lead = exigir_lead(ctx)
    texto = ctx.interpolar(config['texto']).truncate(255)
    return { saida: 's', resumo: "faria: atividade \"#{texto.truncate(80)}\"" } if ctx.ensaio?

    lead.lead_activities.create!(account: lead.account, kind: 'fluxo', to_value: texto)
    { saida: 's', resumo: "atividade: #{texto.truncate(80)}" }
  end

  # SDR/Closer (Ramon::Papeis): pessoa escolhida na tela ou o próximo do time (menos leads abertos).
  # A troca grava sdr_changed/closer_changed pelo callback do Lead.
  def trocar_responsavel(config, ctx)
    lead = exigir_lead(ctx)
    papel = config['papel']
    coluna = Ramon::Papeis::COLUNA[papel] || raise(Ramon::Fluxos::PassoImpossivel, "papel desconhecido: #{papel}")
    feito = ja_tem(config, lead, coluna, papel)
    return feito if feito

    pessoa = config['user_id'].present? ? usuario_da_conta(lead, config['user_id']) : Ramon::Papeis.proximo(lead.account, papel)
    return { saida: 's', resumo: "#{papel}: ninguém no time" } if pessoa.nil?
    return { saida: 's', resumo: "faria: #{papel} → #{pessoa.name}" } if ctx.ensaio?

    lead.update!(coluna => pessoa.id)
    { saida: 's', resumo: "#{papel} → #{pessoa.name}" }
  end

  # B4.1: "só se ainda não tem" (o Closer automático da reunião marcada não troca quem já está).
  def ja_tem(config, lead, coluna, papel)
    return unless config['so_se_vazio'] && lead[coluna].present?

    { saida: 's', resumo: "#{papel}: já tem #{User.find_by(id: lead[coluna])&.name}" }
  end

  # Grava em custom_attributes['campos'] (nunca na raiz: zapsign/advbox/doc_status são do hub).
  # Lição lost update: relê e junta só a chave do fluxo. Nome reservado do hub seria invisível em `dados`.
  def preencher_campo(config, ctx)
    lead = exigir_lead(ctx)
    chave = config['chave']
    raise Ramon::Fluxos::PassoImpossivel, "#{chave} é um nome reservado do hub" if Ramon::Fluxos::Contexto::RESERVADAS.include?(chave)

    valor = ctx.interpolar(config['valor']).truncate(500)
    return { saida: 's', resumo: "faria: #{chave} = #{valor.truncate(60)}" } if ctx.ensaio?

    lead.reload
    campos = (lead.custom_attributes['campos'] || {}).merge(chave => valor)
    lead.update!(custom_attributes: lead.custom_attributes.to_h.merge('campos' => campos))
    { saida: 's', resumo: "#{chave} = #{valor.truncate(60)}" }
  end

  def usuario_da_conta(lead, user_id)
    lead.account.users.find_by(id: user_id) || raise(Ramon::Fluxos::PassoImpossivel, 'a pessoa escolhida não está mais na conta')
  end

  def responsavel_da_tarefa(lead, config)
    config['responsavel_id'].present? ? usuario_da_conta(lead, config['responsavel_id']) : (lead.closer || lead.sdr)
  end

  def kind_da_tarefa(config)
    LeadTask::KINDS.include?(config['tipo']) ? config['tipo'] : 'other'
  end

  def exigir_lead(ctx)
    ctx.lead || raise(Ramon::Fluxos::PassoImpossivel, 'este passo precisa de um lead')
  end
end
