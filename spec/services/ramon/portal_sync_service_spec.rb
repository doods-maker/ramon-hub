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
    allow(Ramon::AdvboxClient).to receive(:lawsuits).with(identification: '12345678901', limit: 20).and_return(lawsuits)
    allow(Ramon::AdvboxClient).to receive(:movements).with(14_039_119, limit: 30).and_return(movements)
    allow(Ramon::AdvboxClient).to receive(:posts).with(lawsuit_id: 14_039_119, limit: 50).and_return(posts)
  end

  it 'espelha processos, andamentos e só os pedidos de documento abertos' do
    processos = described_class.new(cliente).perform
    p = processos.first
    expect(p.slice('id', 'numero', 'etapa', 'fase', 'responsavel_id'))
      .to eq('id' => 14_039_119, 'numero' => '5003800-40.2022.4.04.7207', 'etapa' => 'FASE DE INSTRUÇÃO',
             'fase' => 'JUDICIAL', 'responsavel_id' => 259_713)
    expect(p['andamentos']).to eq([{ 'data' => '2026-06-01', 'titulo' => 'Perícia realizada' }])
    expect(p['docs_pendentes']).to eq([{ 'item' => 'CNIS atualizado', 'post_id' => 1 }, { 'item' => 'Laudo médico', 'post_id' => 1 }])
    expect(cliente.reload.sincronizado_em).to be_present
  end

  it 'sem CPF não chama a API e mantém o espelho' do
    cliente.update!(cpf: nil, processos: [{ 'id' => 1 }])
    expect(described_class.new(cliente).perform).to eq([{ 'id' => 1 }])
    expect(Ramon::AdvboxClient).not_to have_received(:lawsuits)
  end
end
