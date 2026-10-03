require 'rails_helper'

RSpec.describe Ramon::ClienteDaConversa do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5548991203381') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:numero) { '5003412-18.2024.4.04.7207' }
  let(:processo) do
    { 'numero' => numero, 'tipo' => 'Auxílio-doença', 'inicio' => '2023-03-10', 'responsavel' => 'TAMIRES', 'responsavel_id' => 7,
      'fase' => 'Perícia', 'andamentos' => [{ 'data' => '2026-09-12', 'titulo' => 'Petição juntada' },
                                            { 'data' => '2026-09-30', 'titulo' => 'Perícia designada' }] }
  end
  let(:tarefas) do
    [{ 'date' => '2026-10-07 09:00:00', 'task' => 'ACOMPANHAR PERÍCIA', 'notes' => 'INSS Tubarão',
       'users' => [{ 'user_id' => 7 }], 'lawsuit' => { 'process_number' => numero } },
     { 'date' => '2026-10-06 00:00:00', 'task' => 'LIGAR PRO CLIENTE', 'users' => [], 'lawsuit' => { 'process_number' => numero } }]
  end

  # segunda 10h em SP: fora do expediente o ADVBOX não é chamado (Ramon::AdvboxCache)
  around { |example| travel_to(Time.zone.parse('2026-10-05 13:00:00 UTC')) { example.run } }

  before do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(Ramon::AdvboxClient).to receive(:settings).and_return('users' => [{ 'id' => 7, 'email' => 'tamires@banca.adv.br' }])
    allow(Ramon::AdvboxClient).to receive(:posts).and_return('data' => tarefas)
  end

  it 'número que não está no painel do cliente → cliente: false' do
    expect(described_class.new(conversation).perform).to eq(cliente: false)
  end

  context 'with cliente no painel (telefone sem o 55)' do
    let!(:tamires) { create(:user, account: account, email: 'tamires@banca.adv.br', name: 'Dra. Tamires') }

    before { create(:portal_cliente, account: account, telefone: '48991203381', nome: 'Maria', processos: [processo]) }

    it 'monta cliente, processos, advogada e o compromisso da semana' do
      dados = described_class.new(conversation).perform
      expect(dados).to include(cliente: true, nome: 'Maria', desde: '2023-03', telefone: '+5548991203381', sugestao_user_id: tamires.id,
                               advogada: { nome: 'Dra. Tamires', user_id: tamires.id })
      expect(dados[:processos].first).to include(numero: numero, tipo: 'Auxílio-doença', fase: 'Perícia',
                                                 ultimo_andamento: { data: '2026-09-30', titulo: 'Perícia designada' })
      expect(dados[:compromisso]).to eq(tipo: 'pericia', data: '2026-10-07', hora: '09:00', notas: 'INSS Tubarão')
    end

    it 'acha também o celular gravado sem o 9º dígito' do
      PortalCliente.update_all(telefone: '4891203381') # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.new(conversation).perform).to include(cliente: true, nome: 'Maria')
    end

    it 'ADVBOX fora: zera só o compromisso' do
      allow(Ramon::AdvboxClient).to receive(:posts).and_raise(Ramon::AdvboxClient::UnavailableError)
      dados = described_class.new(conversation).perform
      expect(dados).to include(cliente: true, compromisso: nil, sugestao_user_id: tamires.id)
    end
  end
end
