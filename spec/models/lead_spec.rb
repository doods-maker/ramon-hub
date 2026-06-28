require 'rails_helper'

RSpec.describe Lead do
  let(:account) { create(:account) }

  it 'pertence a uma etapa e expõe push_event_data' do
    stage = create(:lead_stage, account: account, name: 'Etapa 3A')
    lead = create(:lead, account: account, lead_stage: stage, name: 'João')

    expect(lead.lead_stage).to eq(stage)
    expect(lead.push_event_data).to include(id: lead.id, name: 'João', lead_stage_id: stage.id)
  end

  it 'exige etapa' do
    lead = build(:lead, account: account, lead_stage: nil)
    expect(lead).not_to be_valid
  end
end
