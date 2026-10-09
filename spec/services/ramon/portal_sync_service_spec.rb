# spec/services/ramon/portal_sync_service_spec.rb
require 'rails_helper'

RSpec.describe Ramon::PortalSyncService do
  let(:cliente) { create(:portal_cliente, cpf: '12345678901') }
  let(:lawsuits) do
    { 'data' => [{ 'id' => 14_039_119, 'process_number' => '5003800-40.2022.4.04.7207', 'type' => 'AUXÍLIO-ACIDENTE',
                   'process_date' => '2022-05-02', 'responsible' => 'RAMON ANTONIO', 'responsible_id' => 259_713,
                   'stage' => 'FASE DE INSTRUÇÃO', 'step' => 'JUDICIAL' }] }
  end
  let(:movements) { { 'data' => [{ 'date' => '2026-06-01', 'title' => 'Perícia realizada', 'header' => 'x' }] } }
  let(:posts) do
    { 'data' => [
      { 'id' => 1, 'task' => 'SOLICITAR DOCUMENTOS', 'notes' => "CNIS atualizado\nLaudo médico\n",
        'users' => [{ 'user_id' => 259_713, 'completed' => nil }] },
      { 'id' => 2, 'task' => 'SOLICITAR DOCUMENTOS', 'notes' => 'RG', 'users' => [{ 'completed' => '2026-08-01 10:00:00' }] },
      { 'id' => 3, 'task' => 'ACOMPANHAR PERÍCIA', 'notes' => 'interno', 'users' => [{ 'completed' => nil }] }
    ] }
  end

  before do
    allow(Ramon::AdvboxClient).to receive(:lawsuits).with(identification: '12345678901', limit: 10).and_return(lawsuits)
    allow(Ramon::AdvboxClient).to receive(:movements).with(14_039_119, limit: 100).and_return(movements)
    allow(Ramon::AdvboxClient).to receive(:posts).with(lawsuit_id: 14_039_119, limit: 50).and_return(posts)
    allow(Ramon::PortalDocsService).to receive(:itens).and_return(['CNIS atualizado', 'Laudo médico'])
    allow(Ramon::AdvboxClient).to receive(:customer).and_return({ 'cellphone' => '(48) 99999-0000' })
  end

  it 'busca o telefone no ADVBOX só enquanto o cliente não tem' do
    described_class.new(cliente).perform
    described_class.new(cliente.reload).perform
    expect(cliente.reload.telefone).to eq '48999990000'
    expect(Ramon::AdvboxClient).to have_received(:customer).once
  end

  it '1º sync não gera novidade; mudança de etapa no sync seguinte gera' do
    expect(described_class.new(cliente).perform.first['novidades']).to eq([])
    lawsuits['data'].first['stage'] = 'SENTENÇA PROFERIDA'
    novidade = described_class.new(cliente.reload).perform.first['novidades'].first
    expect(novidade).to include('tipo' => 'etapa', 'titulo' => 'Juiz deu a sentença', 'delicada' => true, 'vista' => false, 'avisada' => false)
  end

  it 'espelha processos, andamentos e só os pedidos de documento abertos' do
    processos = described_class.new(cliente).perform
    p = processos.first
    expect(p.slice('id', 'numero', 'etapa', 'fase', 'responsavel_id'))
      .to eq('id' => 14_039_119, 'numero' => '5003800-40.2022.4.04.7207', 'etapa' => 'FASE DE INSTRUÇÃO',
             'fase' => 'JUDICIAL', 'responsavel_id' => 259_713)
    expect(p['andamentos']).to eq([{ 'data' => '2026-06-01', 'titulo' => 'Perícia realizada' }])
    expect(p['docs_pendentes'].map { |d| d.slice('item', 'post_id') })
      .to eq([{ 'item' => 'CNIS atualizado', 'post_id' => 1 }, { 'item' => 'Laudo médico', 'post_id' => 1 }])
    expect(p['docs_pendentes'].first['digest']).to be_present
    expect(Ramon::PortalDocsService).to have_received(:itens).once.with("CNIS atualizado
Laudo médico
", nome: cliente.nome, account: cliente.account)
    expect(cliente.reload.sincronizado_em).to be_present
  end

  it 'agenda: só audiência/perícia aberta e ainda por vir, com o formato das observações; 1 chamada de tarefas' do
    posts['data'] += [
      { 'id' => 4, 'task' => 'AUDIÊNCIA DE INSTRUÇÃO/JULGAMENTO', 'date' => '2099-03-09 16:00:00', 'notes' => 'PRESENCIAL',
        'users' => [{ 'completed' => nil }] },
      { 'id' => 5, 'task' => 'AUDIÊNCIA DE CONCILIAÇÃO', 'date' => '2020-01-10 14:00:00', 'notes' => nil, 'users' => [{ 'completed' => nil }] },
      { 'id' => 6, 'task' => 'AVISAR CLIENTE DA AUDIÊNCIA', 'date' => '2099-03-01 00:00:00', 'notes' => nil, 'users' => [{ 'completed' => nil }] }
    ]
    lawsuits['data'].first['protocol_number'] = '547629991'
    p = described_class.new(cliente).perform.first
    expect(p['agenda']).to eq([{ 'tipo' => 'audiencia', 'quando' => '2099-03-09 16:00:00', 'formato' => 'presencial' }])
    expect(p['protocolo']).to eq '547629991'
    expect(Ramon::AdvboxClient).to have_received(:posts).once
  end

  it 'com os textos v2 ligados, sem autorização da IA o pedido vira 1 item resumido e a IA não é chamada' do
    with_modified_env PORTAL_TEXTOS_V2: 'on' do
      itens = described_class.new(cliente).perform.first['docs_pendentes'].map { |d| d['item'] }
      expect(itens).to eq([described_class::ITEM_SEM_IA])
      expect(Ramon::PortalDocsService).not_to have_received(:itens)
      cliente.reload.update!(ia_consentimento: true)
      itens = described_class.new(cliente).perform.first['docs_pendentes'].map { |d| d['item'] }
      expect(itens).to eq(['CNIS atualizado', 'Laudo médico'])
    end
  end

  it 'reaproveita os itens do espelho enquanto as observações da tarefa não mudam' do
    described_class.new(cliente).perform
    described_class.new(cliente.reload).perform
    expect(Ramon::PortalDocsService).to have_received(:itens).once
  end

  it 'LLM falhou (nil) → sem itens e sem cache, tenta de novo no próximo sync' do
    allow(Ramon::PortalDocsService).to receive(:itens).and_return(nil, ['RG'])
    expect(described_class.new(cliente).perform.first['docs_pendentes']).to eq([])
    expect(described_class.new(cliente.reload).perform.first['docs_pendentes'].map { |d| d['item'] }).to eq(['RG'])
  end
end
