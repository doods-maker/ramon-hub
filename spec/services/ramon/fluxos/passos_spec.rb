require 'rails_helper'

RSpec.describe 'Ramon::Fluxos::Passos' do
  let(:account) { create(:account) }
  let(:conversa) { create(:conversation, account: account) }
  let(:lead) { create(:lead, account: account, conversation: conversa, contact: conversa.contact) }
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' })) }

  def ctx(alvo: lead, ensaio: false, contexto: {})
    Ramon::Fluxos::Contexto.new(fluxo.execucoes.create!(account: account, alvo: alvo, ensaio: ensaio, contexto: contexto))
  end

  it 'rascunho vira nota privada com o prefixo, nunca mensagem pública' do
    r = Ramon::Fluxos::Passos::Conversa.rascunho_texto({ 'texto' => 'Oi {nome}' }, ctx)
    msg = conversa.messages.last
    expect(msg.private).to be(true)
    expect(msg.content).to start_with(Ramon::RascunhoCarimbo::PREFIXO)
    expect(r[:saida]).to eq('s')
  end

  it 'rascunho de lead sem conversa vira nota do lead' do
    sozinho = create(:lead, account: account)
    Ramon::Fluxos::Passos::Conversa.rascunho_texto({ 'texto' => 'Oi' }, ctx(alvo: sozinho))
    expect(sozinho.lead_notes.last.body).to start_with(Ramon::RascunhoCarimbo::PREFIXO)
  end

  it 'ensaio não grava nada' do
    expect do
      r = Ramon::Fluxos::Passos::Conversa.rascunho_texto({ 'texto' => 'Oi' }, ctx(ensaio: true))
      expect(r[:resumo]).to start_with('faria: ')
    end.not_to(change { conversa.messages.count })
  end

  it 'ação do Chatwoot põe etiqueta e ignora envio ao cliente' do
    acoes = [{ 'action_name' => 'add_label', 'action_params' => ['urgente'] },
             { 'action_name' => 'send_message', 'action_params' => ['oi'] }]
    expect do
      Ramon::Fluxos::Passos::Conversa.acao_chatwoot({ 'acoes' => acoes }, ctx)
    end.not_to(change { conversa.messages.where(message_type: :outgoing, private: false).count })
    expect(conversa.reload.label_list).to include('urgente')
  end

  it 'ação do Chatwoot fora da lista permitida é descartada antes de rodar' do
    acoes = [{ 'action_name' => 'add_label', 'action_params' => ['urgente'] }, { 'action_name' => 'system', 'action_params' => [] }]
    servico = Ramon::Fluxos::AcaoChatwootService.new(ctx.execucao, conversa, acoes)
    expect(servico.instance_variable_get(:@rule).actions.pluck('action_name')).to eq(['add_label'])
    servico.perform
    expect(conversa.reload.label_list).to include('urgente')
  end

  it 'mover etapa atualiza a etapa inicial da execução' do
    nova = create(:lead_stage, account: account, position: 5)
    c = ctx
    Ramon::Fluxos::Passos::Lead.mover_etapa({ 'etapa_id' => nova.id }, c)
    expect(lead.reload.lead_stage).to eq(nova)
    expect(c.execucao.contexto['etapa_inicial_id']).to eq(nova.id)
  end

  it 'passo de lead sem lead é impossível (não repete)' do
    sem_lead = create(:conversation, account: account)
    expect do
      Ramon::Fluxos::Passos::Lead.mover_etapa({ 'etapa_id' => lead.lead_stage_id }, ctx(alvo: sem_lead))
    end.to raise_error(Ramon::Fluxos::PassoImpossivel)
  end

  it 'tarefa na Esteira com prazo relativo' do
    Ramon::Fluxos::Passos::Lead.criar_tarefa({ 'titulo' => 'Conferir docs de {nome}', 'prazo_dias' => 2 }, ctx)
    tarefa = lead.lead_tasks.last
    expect(tarefa.title).to start_with('Conferir docs de')
    expect(tarefa.due_at.in_time_zone('America/Sao_Paulo').to_date).to eq(Time.find_zone!('America/Sao_Paulo').today + 2)
  end

  it 'esperar devolve o momento de retomar' do
    freeze_time do
      r = Ramon::Fluxos::Passos::Logica.esperar({ 'quantidade' => 2, 'unidade' => 'dias' }, ctx)
      expect(r[:esperar_ate]).to eq(2.days.from_now)
    end
  end

  describe 'esperar antes da reunião (B4.1)' do
    let(:config) { { 'antes_de' => 'reuniao', 'quantidade' => 8, 'unidade' => 'horas' } }
    let(:gatilho) { { 'gatilho' => { 'inicio' => '2026-10-07T22:00:00Z' } } }

    it 'conta para trás a partir da reunião do gatilho' do
      travel_to(Time.zone.parse('2026-10-07T12:00:00Z')) do
        r = Ramon::Fluxos::Passos::Logica.esperar(config, ctx(contexto: gatilho))
        expect(r[:esperar_ate]).to eq(Time.zone.parse('2026-10-07T14:00:00Z'))
        expect(r[:vars]).to eq('horario_passou' => 'nao')
      end
    end

    it 'horário já passado: segue sem esperar e marca horario_passou = sim (o código também não agenda)' do
      travel_to(Time.zone.parse('2026-10-07T15:00:00Z')) do
        r = Ramon::Fluxos::Passos::Logica.esperar(config, ctx(contexto: gatilho))
        expect(r[:esperar_ate]).to be_nil
        expect(r[:vars]).to eq('horario_passou' => 'sim')
        expect(r[:resumo]).to include('já passou')
      end
    end

    it 'sem reunião nenhuma é erro de configuração (não repete)' do
      expect { Ramon::Fluxos::Passos::Logica.esperar(config, ctx) }.to raise_error(Ramon::Fluxos::PassoImpossivel, /reunião/)
    end
  end

  it 'escolha sai pela chave do caso' do
    lead.update!(source: 'indicacao')
    config = { 'campo' => 'origem', 'casos' => [{ 'chave' => 'c1', 'rotulo' => 'Indicação', 'valores' => ['indicacao'] },
                                                { 'chave' => 'c2', 'rotulo' => 'Anúncio', 'valores' => ['anuncio'] }] }
    expect(Ramon::Fluxos::Passos::Logica.escolha(config, ctx)[:saida]).to eq('c1')
  end

  it 'sino avisa o responsável' do
    agente = create(:user, account: account)
    lead.update!(closer: agente)
    expect do
      Ramon::Fluxos::Passos::Aviso.avisar_sino({ 'texto' => 'Ver {nome}' }, ctx)
    end.to change { agente.notifications.where(notification_type: 'ramon_fluxo_aviso').count }.by(1)
  end

  it 'sino sem responsável não cai em todo mundo' do
    create(:user, account: account)
    r = nil
    expect { r = Ramon::Fluxos::Passos::Aviso.avisar_sino({ 'texto' => 'Ver' }, ctx) }.not_to change(Notification, :count)
    expect(r[:resumo]).to eq('sino: sem responsável')
  end

  it 'sino para Closer e SDR (sem nenhum dos dois, os administradores) e para a conta toda' do
    closer = create(:user, account: account)
    sdr = create(:user, account: account)
    create(:user, account: account, role: :administrator)
    c = ctx
    c.lead.update!(closer: closer, sdr: sdr)
    # o builder cria 1 sino por pessoa a cada chamada (a deduplicação roda em job, não aqui): olhar só as linhas novas
    avisar = lambda do |para|
      antes = Notification.maximum(:id).to_i
      Ramon::Fluxos::Passos::Aviso.avisar_sino({ 'texto' => 'Reunião', 'para' => para }, c)
      Notification.where(notification_type: 'ramon_fluxo_aviso').where('id > ?', antes).pluck(:user_id)
    end
    expect(avisar.call('closer_e_sdr')).to contain_exactly(closer.id, sdr.id)
    c.lead.update!(closer: nil, sdr: nil)
    expect(avisar.call('closer_e_sdr')).to match_array(account.account_users.administrator.pluck(:user_id))
    expect(avisar.call('conta')).to match_array(account.account_users.pluck(:user_id))
  end

  it 'ensaio do sino diz quem receberia, sem gravar nada' do
    ana = create(:user, account: account, name: 'Ana')
    c = ctx(ensaio: true)
    c.lead.update!(closer: ana)
    r = nil
    expect { r = Ramon::Fluxos::Passos::Aviso.avisar_sino({ 'texto' => 'Ver {nome}' }, c) }.not_to change(Notification, :count)
    expect(r[:resumo]).to start_with('faria: sino para Ana: "Ver ')
  end

  it 'etapa só para a frente: quem já está adiante fica onde está' do
    atras = create(:lead_stage, account: account, position: 0)
    c = ctx
    r = Ramon::Fluxos::Passos::Lead.mover_etapa({ 'etapa_id' => atras.id, 'so_para_frente' => true }, c)
    expect(r[:resumo]).to eq("etapa: já está em #{lead.lead_stage.name} (só para a frente)")
    expect(lead.reload.lead_stage).not_to eq(atras)
  end

  it 'Closer só se o lead ainda não tem' do
    ana = create(:user, account: account, name: 'Ana')
    create(:team_member, team: create(:team, account: account, name: 'closer'), user: create(:user, account: account))
    c = ctx
    c.lead.update!(closer: ana)
    r = Ramon::Fluxos::Passos::Lead.trocar_responsavel({ 'papel' => 'closer', 'so_se_vazio' => true }, c)
    expect(r[:resumo]).to eq('closer: já tem Ana')
    expect(lead.reload.closer).to eq(ana)
  end

  it 'registrar atividade escreve na linha do tempo do lead' do
    Ramon::Fluxos::Passos::Lead.registrar_atividade({ 'texto' => 'Boas-vindas para {nome}' }, ctx)
    expect(lead.lead_activities.find_by(kind: 'fluxo').to_value).to start_with('Boas-vindas para')
  end

  it 'trocar responsável: a pessoa escolhida ou o próximo do time' do
    ana = create(:user, account: account)
    c = ctx # uma execução só: a 2ª ativa do mesmo fluxo/lead bateria no índice único
    Ramon::Fluxos::Passos::Lead.trocar_responsavel({ 'papel' => 'closer', 'user_id' => ana.id }, c)
    expect(lead.reload.closer).to eq(ana)
    create(:team_member, team: create(:team, account: account, name: 'sdr'), user: ana)
    r = Ramon::Fluxos::Passos::Lead.trocar_responsavel({ 'papel' => 'sdr' }, c)
    expect(lead.reload.sdr).to eq(ana)
    expect(r[:resumo]).to eq("sdr → #{ana.name}")
  end

  it 'trocar responsável: papel inválido ou pessoa de outra conta é erro de config (sem nova tentativa)' do
    estranha = create(:user, account: create(:account))
    c = ctx
    expect { Ramon::Fluxos::Passos::Lead.trocar_responsavel({ 'papel' => 'chefe' }, c) }
      .to raise_error(Ramon::Fluxos::PassoImpossivel, /papel/)
    expect { Ramon::Fluxos::Passos::Lead.trocar_responsavel({ 'papel' => 'sdr', 'user_id' => estranha.id }, c) }
      .to raise_error(Ramon::Fluxos::PassoImpossivel, /pessoa/)
  end

  it 'trocar responsável com time vazio não quebra' do
    r = Ramon::Fluxos::Passos::Lead.trocar_responsavel({ 'papel' => 'sdr' }, ctx)
    expect(r[:resumo]).to eq('sdr: ninguém no time')
  end

  it 'preencher campo relê o lead e junta só na chave campos' do
    c = ctx
    c.lead # carregado antes da escrita concorrente
    Lead.find(lead.id).update!(custom_attributes: { 'zapsign' => { 'status' => 'signed' } })
    Ramon::Fluxos::Passos::Lead.preencher_campo({ 'chave' => 'beneficio', 'valor' => 'BPC' }, c)
    expect(lead.reload.custom_attributes).to eq('zapsign' => { 'status' => 'signed' }, 'campos' => { 'beneficio' => 'BPC' })
  end

  it 'preencher campo recusa nome reservado do hub' do
    expect { Ramon::Fluxos::Passos::Lead.preencher_campo({ 'chave' => 'nome', 'valor' => 'x' }, ctx) }
      .to raise_error(Ramon::Fluxos::PassoImpossivel, /reservado/)
  end

  it 'RESERVADAS cobre toda chave que o Contexto monta sozinho' do
    c = ctx
    montadas = c.dados.keys - ((lead.custom_attributes['campos'] || {}).keys + (c.execucao.contexto['vars'] || {}).keys)
    expect(montadas - Ramon::Fluxos::Contexto::RESERVADAS).to eq([])
  end

  it 'ensaio dos passos de lead não grava nada' do
    c = ctx(ensaio: true)
    expect do
      Ramon::Fluxos::Passos::Lead.registrar_atividade({ 'texto' => 'a' }, c)
      Ramon::Fluxos::Passos::Lead.preencher_campo({ 'chave' => 'x', 'valor' => 'y' }, c)
    end.not_to(change { [lead.lead_activities.count, lead.reload.custom_attributes] })
  end

  describe 'passos da reunião (B4.1)' do
    let(:agente) { create(:user, account: account, name: 'Bia') }
    let(:gatilho) do
      { 'gatilho' => { 'inicio' => '2026-10-07T22:00:00Z', 'quem_marcou_id' => agente.id, 'titulo_tarefa' => 'Reunião Cal.com: Primeiro',
                       'resumo' => 'Primeiro em 07/10/2026 19:00', 'resumo_antes' => 'Primeiro em 06/10/2026 19:00' } }
    end

    it 'atividade de reunião com tipo, de → para e quem marcou' do
      config = { 'tipo' => 'meeting_rescheduled', 'de' => '{resumo_antes}', 'texto' => '{resumo}' }
      Ramon::Fluxos::Passos::Lead.registrar_atividade(config, ctx(contexto: gatilho))
      atividade = lead.lead_activities.find_by!(kind: 'meeting_rescheduled')
      expect([atividade.from_value, atividade.to_value, atividade.user])
        .to eq(['Primeiro em 06/10/2026 19:00', 'Primeiro em 07/10/2026 19:00', agente])
    end

    it 'tarefa da reunião: vence na hora, é de quem marcou e põe a reunião na agenda' do
      allow(Ramon::Fluxos::Reunioes).to receive(:na_agenda)
      config = { 'titulo' => '{titulo_tarefa}', 'tipo' => 'meeting', 'prazo' => 'reuniao' }
      Ramon::Fluxos::Passos::Lead.criar_tarefa(config, ctx(contexto: gatilho))
      tarefa = lead.lead_tasks.find_by!(kind: 'meeting')
      expect([tarefa.title, tarefa.due_at, tarefa.user]).to eq(['Reunião Cal.com: Primeiro', Time.zone.parse('2026-10-07T22:00:00Z'), agente])
      expect(Ramon::Fluxos::Reunioes).to have_received(:na_agenda).with(tarefa, true)
    end

    it 'ensaio da tarefa diz o prazo; da atividade, o tipo e o de → para' do
      c = ctx(ensaio: true, contexto: gatilho)
      tarefa = Ramon::Fluxos::Passos::Lead.criar_tarefa({ 'titulo' => '{titulo_tarefa}', 'tipo' => 'meeting', 'prazo' => 'reuniao' }, c)
      atividade = Ramon::Fluxos::Passos::Lead.registrar_atividade({ 'tipo' => 'meeting_cancelled', 'texto' => '{resumo}' }, c)
      expect(tarefa[:resumo]).to eq('faria: tarefa "Reunião Cal.com: Primeiro" para 07/10 19:00')
      expect(atividade[:resumo]).to eq('faria: atividade meeting_cancelled: Primeiro em 07/10/2026 19:00')
      expect(lead.lead_tasks.count + lead.lead_activities.where(kind: 'meeting_cancelled').count).to eq(0)
    end

    it 'rascunho nas notas do lead com o título do código, mesmo com conversa' do
      config = { 'onde' => 'notas_do_lead', 'titulo' => 'confirmação de reunião', 'texto' => 'Oi {nome}!' }
      expect { Ramon::Fluxos::Passos::Conversa.rascunho_texto(config, ctx) }.not_to(change { conversa.messages.count })
      expect(lead.lead_notes.last.body).to start_with("RASCUNHO (revisar antes de enviar) — confirmação de reunião:
Oi ")
    end

    it 'apagar a reunião: só as tarefas de reunião do evento, do próprio lead' do
      t1 = create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'R1', due_at: 1.day.from_now)
      t2 = create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'R2', due_at: 2.days.from_now)
      outra = create(:lead_task, account: account, lead: create(:lead, account: account), kind: 'meeting', title: 'X', due_at: 1.day.from_now)
      r = Ramon::Fluxos::Passos::Reuniao.apagar_reuniao({}, ctx(contexto: { 'gatilho' => { 'tarefa_ids' => [t1.id, outra.id] } }))
      expect(LeadTask.where(id: [t1.id, t2.id, outra.id]).pluck(:id)).to contain_exactly(t2.id, outra.id)
      expect(r[:resumo]).to eq("apagou tarefas ##{t1.id}") # lista o que apagou de fato
    end
  end
end
