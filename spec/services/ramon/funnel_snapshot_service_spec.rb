require 'rails_helper'

RSpec.describe Ramon::FunnelSnapshotService do
  let(:account) { create(:account) }
  let(:novo) { account.lead_stages.find_by(name: 'Novo') }
  let(:aux) { Thesis.create!(account: account, name: 'Auxílio-acidente') }
  let(:bpc) { Thesis.create!(account: account, name: 'BPC') }

  it 'grava uma linha por etapa x tese com contagem e soma' do
    create(:lead, account: account, lead_stage: novo, thesis: aux, value: 1000)
    create(:lead, account: account, lead_stage: novo, thesis: aux, value: 500)
    create(:lead, account: account, lead_stage: novo, thesis: bpc, value: 300)

    described_class.new(account: account, date: Time.zone.today).perform

    rows = FunnelSnapshot.where(account: account, snapshot_date: Time.zone.today)
    aux_row = rows.find_by(thesis_id: aux.id)
    expect(rows.count).to eq(2)
    expect(aux_row.leads_count).to eq(2)
    expect(aux_row.value_sum).to eq(1500)
    expect(aux_row.stage_name).to eq('Novo')
    expect(aux_row.is_won).to be(false)
  end

  it 'é idempotente: re-rodar o mesmo dia não duplica' do
    create(:lead, account: account, lead_stage: novo, thesis: aux, value: 1000)
    2.times { described_class.new(account: account, date: Time.zone.today).perform }
    expect(FunnelSnapshot.where(account: account, snapshot_date: Time.zone.today).count).to eq(1)
  end

  it 'grava leads sem tese com thesis_name nulo' do
    create(:lead, account: account, lead_stage: novo, value: 700)
    described_class.new(account: account, date: Time.zone.today).perform
    row = FunnelSnapshot.find_by(account: account, lead_stage_id: novo.id, thesis_id: nil)
    expect(row.thesis_name).to be_nil
    expect(row.value_sum).to eq(700)
  end
end
