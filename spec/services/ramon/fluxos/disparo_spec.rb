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

  it 'ensaio do rascunho roda na hora e não grava nada' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' }, nota))
    fluxo.update!(rascunho: grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'quantidade' => 1, 'unidade' => 'dias' }], nota))
    e = nil
    expect { e = described_class.ensaiar(fluxo, lead, usar: 'rascunho') }.not_to(change { conversa.messages.count })
    expect(e).to have_attributes(status: 'concluida', ensaio: true, versao_id: nil)
    expect(e.trilha.pluck('no')).to eq(%w[g p1 p2])
  end

  it 'manual só para fluxo ligado com gatilho manual' do
    manual = fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' }, nota))
    outro = fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_criado' }, nota))
    desligado = fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' }, nota), ativo: false)
    expect(described_class.manual(manual, lead)).to be_a(FluxoExecucao)
    expect(described_class.manual(outro, lead)).to be_nil
    expect(described_class.manual(desligado, lead)).to be_nil
  end
end
