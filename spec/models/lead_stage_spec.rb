require 'rails_helper'

RSpec.describe LeadStage do
  let(:account) { create(:account) }

  it 'valida nome único por conta e ordena por position' do
    account.lead_stages.create!(name: 'Novo', position: 0)
    dup = account.lead_stages.build(name: 'Novo', position: 1)
    expect(dup).not_to be_valid

    account.lead_stages.create!(name: 'Fechado', position: 2)
    expect(account.lead_stages.pluck(:name).first).to eq('Novo')
  end
end
