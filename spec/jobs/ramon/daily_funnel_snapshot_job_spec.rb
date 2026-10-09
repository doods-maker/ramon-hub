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

  it 'regra fixa (08/10): o cron roda todas as contas, sem perguntar a fluxo nenhum' do
    outra = create(:account)
    allow(Ramon::FunnelSnapshotService).to receive(:new).and_call_original
    described_class.perform_now
    expect(Ramon::FunnelSnapshotService).to have_received(:new).with(account: outra)
    expect(described_class.instance_method(:perform).arity).to eq(0) # sem "só esta conta": não há fluxo que peça
  end
end
