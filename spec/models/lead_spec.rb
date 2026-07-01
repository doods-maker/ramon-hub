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

  it 'expõe as colunas A1 (value, source, notes)' do
    expect(described_class.column_names).to include('value', 'source', 'notes')
  end

  it 'push_event_data inclui os campos do card rico' do
    stage = account.lead_stages.find_by(name: 'Negociação')
    lead = create(:lead, account: account, lead_stage: stage, value: 5000, source: 'Indicação')
    data = lead.push_event_data
    expect(data).to include(
      value: lead.value, source: 'Indicação',
      stage_name: 'Negociação', stage_color: '#f59e0b'
    )
    expect(data.keys).to include(:benefit_type_name, :lead_priority_name, :sdr_name, :closer_name, :contact_name)
  end

  context 'lead activities' do
    before { Current.user = nil }
    after { Current.user = nil }

    it 'records a created activity on creation' do
      lead = create(:lead, account: account)
      activity = lead.lead_activities.find_by(kind: 'created')
      expect(activity).to be_present
      expect(activity.user).to be_nil
    end

    it 'records a stage_changed activity with labels and author on stage update' do
      agent = create(:user, account: account)
      novo = create(:lead_stage, account: account, name: 'Fase A')
      prox = create(:lead_stage, account: account, name: 'Fase B')
      lead = create(:lead, account: account, lead_stage: novo)
      Current.user = agent
      lead.update!(lead_stage: prox)
      act = lead.lead_activities.find_by(kind: 'stage_changed')
      expect(act.from_value).to eq('Fase A')
      expect(act.to_value).to eq('Fase B')
      expect(act.user).to eq(agent)
    end

    it 'records a value_changed activity' do
      lead = create(:lead, account: account, value: 100)
      lead.update!(value: 250)
      act = lead.lead_activities.find_by(kind: 'value_changed')
      expect(act.from_value).to eq('100.0')
      expect(act.to_value).to eq('250.0')
    end
  end
end
