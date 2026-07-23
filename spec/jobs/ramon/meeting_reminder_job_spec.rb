require 'rails_helper'

RSpec.describe Ramon::MeetingReminderJob do
  let(:account) { create(:account) }
  let(:lead) { create(:lead, account: account, name: 'Maria da Silva') }
  let(:start_at) { 2.hours.from_now.change(usec: 0) }

  before { allow(Ramon::NtfyPushJob).to receive(:perform_now) }

  it 'com reunião aberta no horário dispara o push com o label' do
    create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'Reunião Cal.com: consulta', due_at: start_at)

    described_class.perform_now(lead.id, start_at.iso8601, '1h antes')

    expect(Ramon::NtfyPushJob).to have_received(:perform_now)
      .with(lead.id, title: 'Reunião Maria da Silva em 1h antes', body: include('confirmação'))
  end

  it 'tolera diferença de até 60s entre o due_at da task e o start_at' do
    create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'Reunião Cal.com: consulta',
                       due_at: start_at + 30.seconds)

    described_class.perform_now(lead.id, start_at.iso8601, '30min antes')

    expect(Ramon::NtfyPushJob).to have_received(:perform_now)
  end

  it 'sem task de reunião aberta é no-op silencioso (cancelada/remarcada)' do
    described_class.perform_now(lead.id, start_at.iso8601, '1h antes')

    expect(Ramon::NtfyPushJob).not_to have_received(:perform_now)
  end

  it 'task concluída não conta como reunião aberta' do
    create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'Reunião Cal.com: consulta',
                       due_at: start_at, completed_at: Time.current)

    described_class.perform_now(lead.id, start_at.iso8601, '1h antes')

    expect(Ramon::NtfyPushJob).not_to have_received(:perform_now)
  end

  it 'task em outro horário (reunião remarcada) não dispara o lembrete órfão' do
    create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'Reunião Cal.com: consulta',
                       due_at: start_at + 3.hours)

    described_class.perform_now(lead.id, start_at.iso8601, '1h antes')

    expect(Ramon::NtfyPushJob).not_to have_received(:perform_now)
  end
end
