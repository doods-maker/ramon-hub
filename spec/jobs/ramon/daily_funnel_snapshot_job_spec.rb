require 'rails_helper'

RSpec.describe Ramon::DailyFunnelSnapshotJob do
  it 'grava o snapshot de hoje para a conta' do
    account = create(:account)
    novo = account.lead_stages.find_by(name: 'Novo')
    create(:lead, account: account, lead_stage: novo, value: 1200)

    described_class.perform_now

    row = FunnelSnapshot.find_by(account: account, snapshot_date: Time.zone.today, lead_stage_id: novo.id)
    expect(row).to be_present
    expect(row.value_sum).to eq(1200)
  end
end
