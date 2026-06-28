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

  it 'dispara LEAD_CREATED ao criar' do
    stage = create(:lead_stage, account: account, name: 'Etapa Disp')
    expect(Rails.configuration.dispatcher).to receive(:dispatch)
      .with(Events::Types::LEAD_CREATED, anything, hash_including(:lead))
    create(:lead, account: account, lead_stage: stage)
  end

  it 'dispara LEAD_UPDATED ao atualizar' do
    stage = create(:lead_stage, account: account, name: 'Etapa Disp2')
    lead = create(:lead, account: account, lead_stage: stage)
    expect(Rails.configuration.dispatcher).to receive(:dispatch)
      .with(Events::Types::LEAD_UPDATED, anything, hash_including(:lead))
    lead.update!(name: 'Novo Nome')
  end
end
