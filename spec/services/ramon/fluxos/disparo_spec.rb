require 'rails_helper'

RSpec.describe Ramon::Fluxos::Disparo do
  let(:account) { create(:account) }
  let(:conversa) { create(:conversation, account: account) }
  let(:lead) { create(:lead, account: account, conversation: conversa, contact: conversa.contact) }
  let(:nota) { ['nota_privada', { 'texto' => 'oi' }] }

  it 'cria execução e enfileira o avanço' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_criado' }, nota))
    expect { described_class.call('lead_criado', lead) }.to have_enqueued_job(Ramon::FluxoAvancarJob)
    e = fluxo.execucoes.last
    expect(e).to have_attributes(status: 'esperando', no_atual: 'p1', profundidade: 0)
    expect(e.retomar_em).to be <= Time.current
    expect(e.trilha.first['tipo']).to eq('gatilho')
    expect(e.contexto['etapa_inicial_id']).to eq(lead.lead_stage_id)
  end

  it 'rajada no mesmo alvo vira uma execução só' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'mensagem_recebida' }, nota))
    5.times { described_class.call('mensagem_recebida', conversa, { 'caixa_id' => conversa.inbox_id }) }
    expect(fluxo.execucoes.count).to eq(1)
  end

  it 'respeita filtro de caixa e de etapa' do
    fluxo_publicado(account, grafo_linear({ 'tipo' => 'conversa_criada', 'caixa_ids' => [conversa.inbox_id + 1] }, nota))
    expect(described_class.call('conversa_criada', conversa, { 'caixa_id' => conversa.inbox_id })).to eq([])

    fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_mudou_etapa', 'para_etapa_ids' => [999] }, nota))
    expect(described_class.call('lead_mudou_etapa', lead, { 'para_etapa_id' => lead.lead_stage_id })).to eq([])
  end

  it 'respeita o limite do dia e ignora desligado' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_criado' }, nota), limite_dia: 1)
    described_class.call('lead_criado', lead)
    described_class.call('lead_criado', create(:lead, account: account))
    expect(fluxo.execucoes.count).to eq(1)

    fluxo.update!(ativo: false)
    expect(described_class.call('lead_criado', create(:lead, account: account))).to eq([])
  end

  it 'cadeia: não redispara a si mesmo e para na profundidade 3' do
    a = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_mudou_etapa' }, nota))
    origem = a.execucoes.create!(account: account, alvo: lead, profundidade: 0, status: 'concluida')
    expect(described_class.call('lead_mudou_etapa', lead, {}, origem: origem)).to eq([])

    b = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_mudou_etapa' }, nota))
    funda = a.execucoes.create!(account: account, alvo: lead, profundidade: 3, status: 'concluida')
    expect(described_class.call('lead_mudou_etapa', lead, {}, origem: funda)).to eq([])
    rasa = a.execucoes.create!(account: account, alvo: lead, profundidade: 1, status: 'concluida')
    expect(described_class.call('lead_mudou_etapa', lead, {}, origem: rasa).map(&:fluxo)).to eq([b])
    expect(b.execucoes.last.profundidade).to eq(2)
  end

  it 'modo sombra cria execução de ensaio' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_criado' }, nota), modo: 'sombra')
    described_class.call('lead_criado', lead)
    expect(fluxo.execucoes.last.ensaio).to be(true)
  end

  it 'cada reunião (tarefa) tem o seu ciclo; remarcar recomeça só o dela (normal e sombra)' do
    espera = ['esperar', { 'quantidade' => 1, 'unidade' => 'dias' }]
    normal = fluxo_publicado(account, grafo_linear({ 'tipo' => 'reuniao_na_agenda' }, espera))
    sombra = fluxo_publicado(account, grafo_linear({ 'tipo' => 'reuniao_na_agenda' }, espera), modo: 'sombra')
    t1 = create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'R1', due_at: 2.days.from_now)
    t2 = create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'R2', due_at: 3.days.from_now)
    [t1, t2, t1].each { |t| described_class.call('reuniao_na_agenda', t, { 'inicio' => t.due_at.iso8601 }) }
    [normal, sombra].each do |f|
      expect(f.execucoes.where(alvo: t1).order(:id).pluck(:status)).to eq(%w[cancelada esperando])
      expect(f.execucoes.where(alvo: t2).pluck(:status)).to eq(%w[esperando])
    end
    expect(normal.execucoes.where(alvo: t1).order(:id).first.trilha.last['resumo']).to eq('cancelado: a reunião foi remarcada')
  end

  it 'com a tarefa da reunião como alvo, o fluxo enxerga o lead e a conversa dela' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'reuniao_na_agenda' }, nota))
    tarefa = create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'R', due_at: 1.day.from_now)
    described_class.call('reuniao_na_agenda', tarefa, {})
    e = fluxo.execucoes.last
    expect([e.lead, e.conversa, e.contexto['etapa_inicial_id']]).to eq([lead, conversa, lead.lead_stage_id])
    expect(e.resumo_json[:alvo_nome]).to eq(lead.name)
  end

  it 'fluxo migrado do código: quem decide se age é o evento (assumido), e roda na hora' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'reuniao_cancelada' }, nota), sistema_chave: 'reuniao_cancelada')
    described_class.call('reuniao_cancelada', lead, { 'assumido' => false })
    described_class.call('reuniao_cancelada', lead, { 'assumido' => true })
    expect(fluxo.execucoes.order(:id).pluck(:ensaio, :status)).to eq([[true, 'concluida'], [false, 'concluida']])
    expect(conversa.messages.where(private: true, content: 'oi').count).to eq(1)
  end

  it 'reunião marcada/cancelada: o disparo com assumido (antes dos efeitos) é só dos migrados; o sem, só dos outros' do
    migrado = fluxo_publicado(account, grafo_linear({ 'tipo' => 'reuniao_marcada' }, nota), sistema_chave: 'reuniao_marcada')
    comum = fluxo_publicado(account, grafo_linear({ 'tipo' => 'reuniao_marcada' }, nota))
    expect(described_class.call('reuniao_marcada', lead, { 'assumido' => false }).map(&:fluxo)).to eq([migrado])
    expect(described_class.call('reuniao_marcada', lead, { 'quando' => 'x' }).map(&:fluxo)).to eq([comum])
    expect([migrado.execucoes.count, comum.execucoes.count]).to eq([1, 1])
  end

  it 'lead ganho (B4.4): o disparo com assumido é só do migrado; o do ouvinte (sem), só dos outros' do
    migrado = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_ganho' }, nota), sistema_chave: 'lead_ganho')
    comum = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_ganho' }, nota))
    expect(described_class.call('lead_ganho', lead, { 'assumido' => true }).map(&:fluxo)).to eq([migrado])
    expect(described_class.call('lead_ganho', lead, { 'para_etapa_id' => lead.lead_stage_id }).map(&:fluxo)).to eq([comum])
    expect(migrado.execucoes.sole.ensaio).to be(false) # assumido = age (não pelo modo)
  end

  it 'eventos do ADVBOX (B4.5): o migrado roda na hora, dentro do job do ADVBOX, e age ou ensaia pela decisão do evento' do
    migrado = fluxo_publicado(account, grafo_linear({ 'tipo' => 'evento_advbox' }, nota), sistema_chave: 'eventos_advbox')
    expect { described_class.call('evento_advbox', lead, { 'assumido' => false, 'regra' => 'marco' }) }
      .not_to have_enqueued_job(Ramon::FluxoAvancarJob)
    described_class.call('evento_advbox', lead, { 'assumido' => true, 'regra' => 'marco' })
    expect(migrado.execucoes.order(:id).pluck(:ensaio, :status)).to eq([[true, 'concluida'], [false, 'concluida']])
    expect(conversa.messages.where(private: true, content: 'oi').count).to eq(1)
  end

  it 'fluxo do sistema nunca roda pelo motor, nem ligado e publicado (D7: quem roda é o código)' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' }, nota), origem: 'sistema')
    expect(described_class.call('manual', lead)).to eq([])
    expect(described_class.manual(fluxo, lead)).to be_nil
    expect(described_class.ensaiar(fluxo, lead)).to be_nil
    expect(fluxo.execucoes.count).to eq(0)
  end

  it 'ensaio do rascunho roda na hora e não grava nada' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' }, nota))
    fluxo.update!(rascunho: grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'quantidade' => 1, 'unidade' => 'dias' }], nota))
    e = nil
    expect { e = described_class.ensaiar(fluxo, lead, usar: 'rascunho') }.not_to(change { conversa.messages.count })
    expect(e).to have_attributes(status: 'concluida', ensaio: true, versao_id: nil)
    expect(e.trilha.pluck('no')).to eq(%w[g p1 p2])
  end

  it 'evento do ADVBOX filtra pela regra' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'evento_advbox', 'regras' => ['exito'] }, nota))
    expect(described_class.call('evento_advbox', lead, { 'regra' => 'marco' })).to eq([])
    described_class.call('evento_advbox', lead, { 'regra' => 'exito' })
    expect(fluxo.execucoes.count).to eq(1)
  end

  it 'externo nunca derruba quem chamou' do
    allow(described_class).to receive(:call).and_raise(StandardError, 'bug no motor')
    expect(described_class.externo('contrato_assinado', lead)).to eq([])
  end

  it 'manual só para fluxo ligado com gatilho manual' do
    manual = fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' }, nota))
    outro = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_criado' }, nota))
    desligado = fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' }, nota), ativo: false)
    expect(described_class.manual(manual, lead)).to be_a(FluxoExecucao)
    expect(described_class.manual(outro, lead)).to be_nil
    expect(described_class.manual(desligado, lead)).to be_nil
  end

  it 'alvo = a conta (B5): nem lead nem conversa, mesmo com uma conversa de mesmo id' do
    conversa = create(:conversation, account: account, id: account.id)
    create(:lead, account: account, conversation_id: conversa.id)
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' }, ['parar', {}]))
    execucao = described_class.new(fluxo, account, {}, nil).iniciar
    expect([execucao.alvo, execucao.lead, execucao.conversa]).to eq([account, nil, nil])
    expect(execucao.contexto).not_to have_key('etapa_inicial_id')
  end

  it 'B5-leads: dois grupos migrados no mesmo gatilho — cada decisão só inicia o fluxo do seu grupo' do
    sla = fluxo_publicado(account, grafo_linear({ 'tipo' => 'conversa_criada' }, nota), sistema_chave: 'sla_primeira_resposta')
    criar = fluxo_publicado(account, grafo_linear({ 'tipo' => 'conversa_criada' }, nota), sistema_chave: 'criar_lead_da_conversa')
    comum = fluxo_publicado(account, grafo_linear({ 'tipo' => 'conversa_criada' }, nota))
    expect(described_class.call('conversa_criada', conversa, { 'assumido' => false, 'migracao' => 'sla' }).map(&:fluxo)).to eq([sla])
    expect(described_class.call('conversa_criada', conversa, { 'assumido' => false, 'migracao' => 'criar_lead' }).map(&:fluxo)).to eq([criar])
    expect(described_class.call('conversa_criada', conversa, { 'caixa_id' => conversa.inbox_id }).map(&:fluxo)).to eq([comum])
  end

  it 'B5-leads: criar lead e origem migrados rodam na hora (dentro do ouvinte); coach, documento e SLA seguem pelo job' do
    origem = fluxo_publicado(account, grafo_linear({ 'tipo' => 'mensagem_recebida' }, nota), sistema_chave: 'origem_do_lead')
    coach = fluxo_publicado(account, grafo_linear({ 'tipo' => 'mensagem_recebida' }, nota), sistema_chave: 'coach_objecao')
    described_class.call('mensagem_recebida', conversa, { 'assumido' => true, 'migracao' => 'origem_lead' })
    expect { described_class.call('mensagem_recebida', conversa, { 'assumido' => true, 'migracao' => 'coach' }) }
      .to have_enqueued_job(Ramon::FluxoAvancarJob)
    expect([origem.execucoes.sole.status, coach.execucoes.sole.status]).to eq(%w[concluida esperando])
  end

  it 'B5-leads: nota privada escrita dispara 2 vezes — com a decisão só o migrado; sem, só os comuns' do
    migrado = fluxo_publicado(account, grafo_linear({ 'tipo' => 'nota_escrita' }, nota), sistema_chave: 'agente_hub')
    comum = fluxo_publicado(account, grafo_linear({ 'tipo' => 'nota_escrita' }, nota))
    expect(described_class.call('nota_escrita', conversa, { 'assumido' => true, 'migracao' => 'agente' }).map(&:fluxo)).to eq([migrado])
    expect(described_class.call('nota_escrita', conversa, { 'texto' => 'oi' }).map(&:fluxo)).to eq([comum])
  end
end
