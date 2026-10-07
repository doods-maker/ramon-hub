# B4.4/B4.5: rotinas prontas do hub como passo de fluxo — o MESMO código de hoje, com as mesmas travas:
# - dossie_passagem: Leads::HandoffNoteService (nas notas do lead; não repete se já há um dos últimos 5 min)
#   Dossiê e NPS do ganho só com o lead ainda ganho, como os callbacks do Lead: execução atrasada não escreve nada.
# - pesquisa_nps / pesquisa_nps_exito: Ramon::NpsDraftJob (rascunho nas notas; 1 vez por fase — nps.pedido_em /
#   nps.pedido_exito_em; link do Google = RAMON_GOOGLE_REVIEW_URL)
# - abrir_caso_advbox: Ramon::AdvboxClosingService (cliente + processo em CONTRATO FECHADO + tarefa 1º CONTATO). Grava no
#   ADVBOX de verdade, com a garantia de hoje: só com ADVBOX_API_TOKEN, nunca de novo com advbox.sincronizado_em, cada id
#   guardado assim que nasce (a nova tentativa do motor retoma dali). Fora do ar sobe o erro → o motor tenta de novo em
#   1/5/15 min; recusa (4xx) fica anotada no lead (advbox.erro), como hoje, e o fluxo segue.
# - concluir_tarefas: conclui as tarefas abertas do lead (ADVBOX arquivado)
module Ramon::Fluxos::Passos::Rotina
  ROTINAS = %w[dossie_passagem pesquisa_nps pesquisa_nps_exito abrir_caso_advbox concluir_tarefas].freeze
  FASE_NPS = { 'pesquisa_nps' => 'comercial', 'pesquisa_nps_exito' => 'exito' }.freeze

  module_function

  def rotina(config, ctx)
    nome = config['rotina'].to_s
    raise Ramon::Fluxos::PassoImpossivel, "rotina desconhecida: #{nome}" unless ROTINAS.include?(nome)

    lead = Ramon::Fluxos::Passos::Lead.exigir_lead(ctx)
    resumo = FASE_NPS.key?(nome) ? nps(lead, FASE_NPS[nome], ctx.ensaio?) : public_send(nome, lead, ctx.ensaio?)
    { saida: 's', resumo: resumo }
  end

  def dossie_passagem(lead, ensaio)
    servico = Leads::HandoffNoteService.new(lead: lead)
    return 'dossiê: já há um dos últimos 5 min (não repete)' if servico.recent_dossier?
    return 'dossiê: o lead não está mais ganho, não escreveu' if lead.won_at.blank?
    return 'faria: dossiê de passagem nas notas do lead' if ensaio

    servico.perform
    'dossiê de passagem nas notas do lead'
  end

  def nps(lead, fase, ensaio)
    pedido = lead.custom_attributes&.dig('nps', Ramon::NpsDraftJob::GUARD_KEYS.fetch(fase))
    return "pesquisa NPS (#{fase}): já pedida em #{pedido} (uma vez só)" if pedido.present?
    return 'pesquisa NPS (comercial): o lead não está mais ganho, não pediu' if fase == 'comercial' && lead.won_at.blank?
    return "faria: rascunho da pesquisa NPS (#{fase}) nas notas do lead" if ensaio

    Ramon::NpsDraftJob.perform_now(lead.id, fase: fase)
    "rascunho da pesquisa NPS (#{fase}) nas notas do lead"
  end

  def abrir_caso_advbox(lead, ensaio)
    feito = lead.custom_attributes&.dig('advbox', 'sincronizado_em')
    return "ADVBOX: caso já aberto em #{feito} (não chama de novo)" if feito.present?
    return 'ADVBOX: sem token no hub, não abriu o caso (como o código)' if ENV.fetch('ADVBOX_API_TOKEN', nil).blank?
    return 'ADVBOX: o lead não está mais ganho, não abriu o caso' if lead.won_at.blank?
    return 'faria: abrir o caso no ADVBOX (cliente, processo em CONTRATO FECHADO e tarefa 1º CONTATO)' if ensaio

    Ramon::AdvboxClosingService.new(lead).perform
    advbox = lead.reload.custom_attributes['advbox'].to_h
    return "ADVBOX recusou: #{advbox['erro'].truncate(120)} (anotado no lead)" if advbox['erro'].present?

    "caso aberto no ADVBOX (processo #{advbox['lawsuits_id']})"
  end

  def concluir_tarefas(lead, ensaio)
    abertas = lead.lead_tasks.open_tasks
    return "faria: concluir #{abertas.count} tarefa(s) aberta(s) do lead" if ensaio

    concluidas = abertas.update_all(completed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    "concluiu #{concluidas} tarefa(s) aberta(s) do lead"
  end
end
