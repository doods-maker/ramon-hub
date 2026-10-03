require 'rails_helper'

RSpec.describe Ramon::AdvboxCache do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:chamadas) { [] }
  let(:busca) { -> { described_class.buscar('ramon/teste', expires_in: 30.minutes) { (chamadas << 1) && ['ok'] } } }

  before { allow(Rails).to receive(:cache).and_return(cache) }

  context 'when in office hours (segunda 10h em SP)' do
    around { |example| travel_to(Time.zone.parse('2026-10-05 13:00:00 UTC')) { example.run } }

    it 'busca uma vez e serve do cache' do
      2.times { busca.call }
      expect(chamadas.size).to eq(1)
    end

    it 'falhou: pausa 10 min sem chamar o ADVBOX, depois volta' do
      expect do
        described_class.buscar('ramon/teste', expires_in: 30.minutes) { raise Ramon::AdvboxClient::UnavailableError, 'caiu' }
      end.to raise_error(Ramon::AdvboxClient::UnavailableError)
      expect { busca.call }.to raise_error(Ramon::AdvboxClient::UnavailableError, /pausa/)
      expect(chamadas).to be_empty

      travel 11.minutes
      expect(busca.call).to eq(['ok'])
    end
  end

  it 'fora do expediente não chama: usa o cache ou devolve vazio' do
    travel_to(Time.zone.parse('2026-10-04 13:00:00 UTC')) do # domingo
      expect(busca.call).to eq([])
      cache.write('ramon/teste', ['guardado'])
      expect(busca.call).to eq(['guardado'])
    end
    travel_to(Time.zone.parse('2026-10-05 23:30:00 UTC')) { expect(busca.call).to eq(['guardado']) } # 20h30 de SP
    expect(chamadas).to be_empty
  end
end
