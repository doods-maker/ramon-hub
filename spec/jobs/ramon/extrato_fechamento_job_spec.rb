require 'rails_helper'

RSpec.describe Ramon::ExtratoFechamentoJob do
  let(:account) { create(:account) }
  let(:sdr) { create(:user, account: account, role: :agent) }

  before { create(:team_member, team: create(:team, account: account, name: 'sdr'), user: sdr) }

  it 'fecha o mês anterior só a partir do 3º dia útil', :aggregate_failures do
    travel_to(Time.zone.parse('2026-12-02 15:00:00 UTC')) { described_class.perform_now }
    expect(ExtratoFechado.count).to eq(0)

    travel_to(Time.zone.parse('2026-12-03 15:00:00 UTC')) { described_class.perform_now }
    expect(ExtratoFechado.where(account: account, competencia: Date.new(2026, 11, 1)).pluck(:user_id)).to eq([sdr.id])
  end

  it 'B5: conta com o fluxo no comando fica de fora do cron; com o id, só ela' do
    allow(Ramon::Fluxos::Migracao).to receive(:assumiu?).and_call_original
    allow(Ramon::Fluxos::Migracao).to receive(:assumiu?).with(account, 'fechamento_extrato').and_return(true)
    travel_to(Time.zone.parse('2026-12-03 15:00:00 UTC')) { described_class.perform_now }
    expect(ExtratoFechado.count).to eq(0)
    travel_to(Time.zone.parse('2026-12-03 15:01:00 UTC')) { described_class.perform_now(account.id) }
    expect(ExtratoFechado.where(account: account).pluck(:user_id)).to eq([sdr.id])
  end
end
