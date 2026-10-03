require 'rails_helper'

RSpec.describe Ramon::SemanaAdvboxService do
  let(:account) { create(:account) }
  let(:tamires) { create(:user, account: account, email: 'tamires@banca.adv.br') }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:tarefas) do
    [
      { 'id' => 1, 'date' => '2026-10-08 00:00:00', 'task' => 'ELABORAR PETIÇÃO INICIAL', 'users' => [{ 'user_id' => 99 }], 'lawsuit' => {} },
      { 'id' => 2, 'date' => '2026-10-07 09:00:00', 'task' => 'ACOMPANHAR PERÍCIA', 'notes' => 'INSS Tubarão', 'users' => [{ 'user_id' => 7 }],
        'lawsuit' => { 'process_number' => '5003412-18.2024.4.04.7207', 'customers' => [{ 'name' => 'MARIA', 'customers_origins_id' => 1 }] } },
      { 'id' => 3, 'date' => '2026-10-06 00:00:00', 'task' => 'LIGAR PRO CLIENTE', 'users' => [{ 'user_id' => 7 }], 'lawsuit' => {} }
    ]
  end

  # Segunda, 10h em SP — dentro do expediente (Ramon::AdvboxCache).
  around { |example| travel_to(Time.zone.parse('2026-10-05 13:00:00 UTC')) { example.run } }

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    allow(Ramon::AdvboxClient).to receive(:settings).and_return('users' => [{ 'id' => 7, 'email' => 'TAMIRES@banca.adv.br' }])
    allow(Ramon::AdvboxClient).to receive(:posts).and_return('data' => tarefas)
  end

  it 'traz só as tarefas da pessoa, em ordem, com destaque e hora' do
    linhas = described_class.new(account).para(tamires)
    expect(linhas.pluck(:tarefa)).to eq(['LIGAR PRO CLIENTE', 'ACOMPANHAR PERÍCIA'])
    expect(linhas.first).to include(destaque: nil, hora: nil, data: '2026-10-06')
    expect(linhas.last).to include(destaque: 'pericia', hora: '09:00', cliente: 'MARIA', processo: '5003412-18.2024.4.04.7207',
                                   notas: 'INSS Tubarão')
  end

  it 'usa cache (uma chamada só pra duas consultas)' do
    described_class.new(account).para(tamires)
    described_class.new(account).para(tamires)
    expect(Ramon::AdvboxClient).to have_received(:posts).once
  end

  it 'pede hoje..hoje+6 de São Paulo' do
    described_class.new(account).para(tamires)
    expect(Ramon::AdvboxClient).to have_received(:posts).with(hash_including(date_start: '2026-10-05', date_end: '2026-10-11', offset: 0))
  end

  describe 'paginação' do
    let(:pagina) { Array.new(100) { |i| { 'id' => i + 1, 'task' => 'X' } } }

    it 'para quando a página vem repetida e não duplica tarefa' do
      allow(Ramon::AdvboxClient).to receive(:posts).and_return({ 'data' => pagina }, { 'data' => pagina })
      expect(described_class.tarefas.size).to eq(100)
      expect(Ramon::AdvboxClient).to have_received(:posts).twice
    end

    it 'para quando bate o totalCount' do
      allow(Ramon::AdvboxClient).to receive(:posts).and_return('data' => pagina, 'totalCount' => 100)
      expect(described_class.tarefas.size).to eq(100)
      expect(Ramon::AdvboxClient).to have_received(:posts).once
    end
  end
end
