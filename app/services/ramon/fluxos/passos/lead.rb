# Passos que mexem no lead (funil e Esteira).
module Ramon::Fluxos::Passos::Lead
  module_function

  # B4.1: tipos de atividade que um fluxo pode registrar (os de reunião aparecem como os do código).
  TIPOS_ATIVIDADE = %w[fluxo meeting_scheduled meeting_rescheduled meeting_cancelled].freeze

  def mover_etapa(config, ctx)
    lead = exigir_lead(ctx)
    etapa = lead.account.lead_stages.find(config['etapa_id'])
    adiante = ja_adiante(config, lead, etapa)
    return adiante if adiante

    # PR #216: perda exige motivo. Com motivo no passo, vai ele; sem, o Lead preenche "Automação: <fluxo>".
    motivo = ctx.interpolar(config['motivo']).strip.presence if etapa.is_lost
    destino = motivo ? "#{etapa.name} (motivo: #{motivo})" : etapa.name
    return { saida: 's', resumo: "faria: mover para #{destino}" } if ctx.ensaio?

    lead.update!({ lead_stage: etapa, lost_reason: motivo }.compact)
    # a mudança feita pelo próprio fluxo não pode cancelá-lo na próxima espera
    ctx.execucao.contexto = ctx.execucao.contexto.merge('etapa_inicial_id' => etapa.id)
    { saida: 's', resumo: "moveu para #{destino}" }
  end

  # B4.1: "só para a frente" (como a reunião marcada do código): quem já está adiante fica onde está.
  def ja_adiante(config, lead, etapa)
    return unless config['so_para_frente'] && lead.lead_stage.position >= etapa.position

    { saida: 's', resumo: "etapa: já está em #{lead.lead_stage.name} (só para a frente)" }
  end

  def criar_tarefa(config, ctx)
    lead = exigir_lead(ctx)
    titulo = ctx.interpolar(config['titulo']).truncate(255)
    prazo = prazo_da_tarefa(config, ctx)
    return { saida: 's', resumo: "faria: tarefa \"#{titulo}\" para #{Ramon::Fluxos::Passos::Logica.hora(prazo)}" } if ctx.ensaio?

    responsavel = responsavel_da_tarefa(lead, config, ctx)
    tarefa = lead.lead_tasks.create!(account: lead.account, kind: kind_da_tarefa(config), title: titulo, due_at: prazo, user: responsavel)
    # B4.1: a tarefa da própria reunião põe a reunião na agenda → começa o ciclo de lembretes dela (fluxos no comando)
    Ramon::Fluxos::Reunioes.na_agenda(tarefa, true) if config['prazo'] == 'reuniao' && tarefa.kind == 'meeting'
    { saida: 's', resumo: "tarefa \"#{titulo}\" · #{responsavel&.name || 'sem responsável'}" }
  end

  # B4.1: tipo (as de reunião iguais às do código), "de" opcional (remarcada: de → para) e a pessoa que marcou.
  def registrar_atividade(config, ctx)
    lead = exigir_lead(ctx)
    tipo = TIPOS_ATIVIDADE.include?(config['tipo']) ? config['tipo'] : 'fluxo'
    texto = ctx.interpolar(config['texto']).truncate(255)
    de = ctx.interpolar(config['de']).truncate(255).presence
    return { saida: 's', resumo: "faria: atividade #{tipo}: #{[de, texto].compact.join(' → ')}" } if ctx.ensaio?

    lead.lead_activities.create!(account: lead.account, user: ctx.quem_marcou, kind: tipo, from_value: de, to_value: texto)
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

  # B4.1: prazo 'reuniao' = vence na hora da reunião do gatilho; senão, N dias a partir de hoje (fim do dia, SP).
  def prazo_da_tarefa(config, ctx)
    return ctx.reuniao_em || raise(Ramon::Fluxos::PassoImpossivel, 'sem reunião marcada para o prazo') if config['prazo'] == 'reuniao'

    (Time.find_zone!(Fluxo::ZONA).now + config.fetch('prazo_dias', 1).to_i.days).end_of_day
  end

  # Tarefa da reunião é de quem marcou (como no código); as outras, a pessoa escolhida ou o responsável do lead.
  def responsavel_da_tarefa(lead, config, ctx)
    return ctx.quem_marcou if config['prazo'] == 'reuniao'

    config['responsavel_id'].present? ? usuario_da_conta(lead, config['responsavel_id']) : (lead.closer || lead.sdr)
  end

  def kind_da_tarefa(config)
    LeadTask::KINDS.include?(config['tipo']) ? config['tipo'] : 'other'
  end

  def exigir_lead(ctx)
    ctx.lead || raise(Ramon::Fluxos::PassoImpossivel, 'este passo precisa de um lead')
  end
end
