require 'rails_helper'

RSpec.describe FunnelSnapshot, type: :model do
  let(:account) { create(:account) }
  let(:stage) { account.lead_stages.find_by(name: 'Novo') }

  it 'persists a snapshot row with denormalized labels' do
    snap = FunnelSnapshot.create!(
      account: account, snapshot_date: Time.zone.today,
      lead_stage: stage, stage_name: stage.name, stage_position: stage.position,
      is_won: false, is_lost: false, thesis_id: nil, thesis_name: nil,
      leads_count: 3, value_sum: 4500
    )
    expect(snap.reload.leads_count).to eq(3)
    expect(snap.value_sum).to eq(4500)
    expect(snap.stage_name).to eq('Novo')
  end

  it 'allows a null lead_stage and thesis (history survives deletes)' do
    snap = FunnelSnapshot.create!(
      account: account, snapshot_date: Time.zone.today,
      stage_name: 'Etapa Removida', stage_position: 9,
      leads_count: 0, value_sum: 0
    )
    expect(snap).to be_persisted
    expect(snap.lead_stage).to be_nil
  end
end
