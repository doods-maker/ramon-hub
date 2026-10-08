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

  it 'B5: conta com o fluxo no comando fica de fora do cron; com o id, só ela' do
    account = create(:account)
    outra = create(:account)
    [account, outra].each { |a| create(:lead, account: a, lead_stage: a.lead_stages.find_by(name: 'Novo')) }
    allow(Ramon::Fluxos::Migracao).to receive(:assumiu?).and_call_original
    allow(Ramon::Fluxos::Migracao).to receive(:assumiu?).with(account, 'retrato_funil').and_return(true)
    described_class.perform_now
    expect([FunnelSnapshot.where(account: account).count, FunnelSnapshot.where(account: outra).count]).to eq([0, 1])
    described_class.perform_now(account.id)
    expect(FunnelSnapshot.where(account: account).count).to eq(1)
  end
end
