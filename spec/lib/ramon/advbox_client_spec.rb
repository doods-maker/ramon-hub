require 'rails_helper'

RSpec.describe Ramon::AdvboxClient do
  around { |ex| with_modified_env('ADVBOX_API_TOKEN' => 'tk') { ex.run } }

  it 'passa limit como query nas leituras' do
    stub_request(:get, "#{described_class::BASE}/movements/7?limit=3").to_return(status: 200, body: '')
    expect { described_class.movements(7, limit: 3) }.not_to raise_error
  end

  it 'processo sem publicação (404) vira lista vazia' do
    stub_request(:get, "#{described_class::BASE}/publications/7?limit=2").to_return(status: 404)
    expect(described_class.publications(7)).to eq([])
  end

  it '404 fora de publications segue como indisponível' do
    stub_request(:get, "#{described_class::BASE}/lawsuits/7").to_return(status: 404)
    expect { described_class.lawsuit(7) }.to raise_error(described_class::UnavailableError)
  end
end
