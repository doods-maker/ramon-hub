require 'rails_helper'

RSpec.describe Leads::SeedDefaultConfigService do
  let(:account) { create(:account) }

  it 'semeia 8 etapas, 7 benefícios e 3 prioridades, idempotente' do
    described_class.new(account).perform
    described_class.new(account).perform # idempotência

    expect(account.lead_stages.count).to eq(8)
    expect(account.benefit_types.count).to eq(7)
    expect(account.lead_priorities.count).to eq(3)
    expect(account.lead_stages.find_by(name: 'Fechado')).to be_is_won
    expect(account.lead_stages.find_by(name: 'Perdido')).to be_is_lost
  end
end
