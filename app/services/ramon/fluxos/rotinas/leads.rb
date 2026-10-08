# B5-leads: leads e conversas pelos fluxos — criar lead, origem, sugestão de documento, coach de objeção e o aviso ao
# agente do hub. Cada uma é uma migração (GRUPOS, juntado em Migracao::GRUPOS pelo registro); o ouvinte decide por
# Ramon::Fluxos::Migracao.decidir, com reserva. Na carga este módulo não cita Ramon::Fluxos::Migracao (autoload circular).
# Rotinas prontas (contrato do registro Ramon::Fluxos::Rotinas): ROTINAS nome → alvo + rodar(nome, ctx), que devolve o
# resultado do passo — o MESMO código de hoje, com as mesmas travas. O ensaio só descreve (sem IA, sem gravar). As de
# mensagem leem a mensagem pelo 'mensagem_id' do gatilho (Mensagem recebida / Nota privada escrita).
# - criar_lead: Ramon::LeadDaConversa.criar_ou_ligar (só caixa com "Criar lead" e conversa com contato)
# - origem_do_lead: Ramon::LeadDaConversa.origem (anúncio da Meta; canal derivado; nunca sobrescreve canal já definido)
# - sugestao_documento: Ramon::DocMatchJob (a IA sugere o item do checklist; daqui nasce o gatilho Documento recebido)
# - coach_objecao: Ramon::CoachObjecaoJob (1 vez a cada 10 min por conversa; qualquer erro = silêncio)
# - agente_hub: Ramon::AgenteNotifyJob (só nota @claude do Eduardo — a trava fica aqui dentro; a tela não a tira. Sem ela
#   a própria resposta do runner, nota por API, dispararia Nota privada escrita de novo: laço)
# Job.new.perform: o corpo do job, na hora — perform_now re-enfileiraria pelo retry_on dele (dobra com o motor).
# Sem balão "⚙ Fluxo" (N3), exceto criar_lead: as de mensagem seriam 1 por mensagem e o efeito já tem o seu balão.
module Ramon::Fluxos::Rotinas::Leads
  GRUPOS = {
    'criar_lead' => { env: 'RAMON_FLUXO_CRIAR_LEAD', faz: 'a criação do lead', fluxos: { 'criar_lead_da_conversa' => 'conversa_criada' }.freeze },
    'origem_lead' => { env: 'RAMON_FLUXO_ORIGEM_LEAD', faz: 'a origem do lead', fluxos: { 'origem_do_lead' => 'mensagem_recebida' }.freeze },
    'sugestao_doc' => { env: 'RAMON_FLUXO_SUGESTAO_DOC', faz: 'a sugestão de documento',
                        fluxos: { 'sugestao_documento' => 'mensagem_recebida' }.freeze },
    'coach' => { env: 'RAMON_FLUXO_COACH', faz: 'o coach de objeção', fluxos: { 'coach_objecao' => 'mensagem_recebida' }.freeze },
    'agente' => { env: 'RAMON_FLUXO_AGENTE', faz: 'o aviso ao agente do hub', fluxos: { 'agente_hub' => 'nota_escrita' }.freeze }
  }.freeze
  # alvo 'conversa' (F6): o gatilho delas é de conversa; criar lead nem tem lead ainda.
  ROTINAS = {
    'criar_lead' => 'conversa', 'origem_do_lead' => 'conversa', 'sugestao_documento' => 'conversa',
    'coach_objecao' => 'conversa', 'agente_hub' => 'conversa'
  }.freeze
  # IA fora do ar ou anexo ainda indisponível: o motor tenta de novo (1/5/15 min); na última, desiste em silêncio (N4).
  PASSAGEIROS = [Ramon::LlmClient::TransientError, ActiveStorage::FileNotFoundError].freeze

  module_function

  def rodar(nome, ctx) = public_send(nome, ctx)

  def criar_lead(ctx)
    conversa = ctx.conversa || raise(Ramon::Fluxos::PassoImpossivel, 'este passo precisa de uma conversa')
    return quieto('a caixa não cria lead (ou a conversa não tem contato): nada feito') unless Ramon::LeadDaConversa.cabe?(conversa)
    return feito('faria: criar o lead na 1ª etapa do funil (ou ligar a conversa ao lead aberto do contato)') if ctx.ensaio?

    lead = Ramon::LeadDaConversa.criar_ou_ligar(conversa)
    feito("#{lead.previously_new_record? ? 'lead criado' : 'conversa ligada ao lead aberto'}: #{lead.name} (#{lead.lead_stage.name})")
  end

  def origem_do_lead(ctx)
    return feito('faria: anotar a origem e o canal do lead (anúncio da Meta, site/LP/bio, instagram ou indicação)') if ctx.ensaio?

    lead = Ramon::Fluxos::Passos::Lead.exigir_lead(ctx)
    Ramon::LeadDaConversa.origem(lead, mensagem!(ctx))
    lead.reload
    quieto("origem do lead: canal #{lead.channel}#{", origem #{lead.source}" if lead.source.present?}")
  end

  def sugestao_documento(ctx)
    return feito('faria: a IA compara o anexo com o checklist da tese e sugere o documento (a equipe confirma)') if ctx.ensaio?

    msg = mensagem!(ctx)
    Ramon::DocMatchJob.new.perform(msg.id)
    casou = ctx.lead&.reload&.custom_attributes&.dig('doc_sugestao', 'message_id') == msg.id
    quieto(casou ? 'a IA sugeriu um documento do checklist (a equipe confirma no painel)' : 'a IA não reconheceu o anexo no checklist pendente')
  rescue *PASSAGEIROS => e
    raise if ctx.execucao.tentativas < Ramon::Fluxos::Executor::ESPERAS_ERRO.size

    quieto("sugestão de documento: desistiu depois de #{ctx.execucao.tentativas + 1} tentativas (#{e.class.name.demodulize})")
  end

  def coach_objecao(ctx)
    return feito('faria: o coach procura objeção na mensagem e sugere 2 respostas do playbook da tese') if ctx.ensaio?

    Ramon::CoachObjecaoJob.new.perform(mensagem!(ctx).id)
    quieto('coach de objeção: leu a mensagem (havendo objeção, as 2 respostas aparecem no balão do coach)')
  end

  def agente_hub(ctx)
    return feito('faria: avisar o agente do hub na VPS (só nota @claude do Eduardo)') if ctx.ensaio?

    msg = mensagem!(ctx)
    return quieto('não é nota @claude do Eduardo: o agente não foi chamado') unless Ramon::AgenteNotifyJob.chamado?(msg)

    Ramon::AgenteNotifyJob.new.perform(msg.id)
    quieto('avisou o agente do hub (a resposta chega como nota privada)')
  end

  def feito(resumo) = { saida: 's', resumo: resumo }

  def quieto(resumo) = feito(resumo).merge(sem_balao: true)

  # A mensagem que disparou o fluxo. Sem ela ("Testar com um lead…" vira ensaio, que não chega aqui): passo impossível.
  def mensagem!(ctx)
    id = ctx.gatilho('mensagem_id')
    (id && ctx.execucao.account.messages.find_by(id: id)) ||
      raise(Ramon::Fluxos::PassoImpossivel, 'este passo precisa da mensagem do gatilho (Mensagem recebida ou Nota privada escrita)')
  end
end
