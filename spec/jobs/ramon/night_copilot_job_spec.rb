require 'rails_helper'

RSpec.describe Ramon::NightCopilotJob do
  let!(:account) { create(:account) }
  let!(:other_account) { create(:account) }

  it 'roda o serviço para cada conta na fila scheduled_jobs' do
    service = instance_double(Ramon::NightCopilotService, perform: 0)
    allow(Ramon::NightCopilotService).to receive(:new).and_return(service)

    described_class.perform_now

    expect(Ramon::NightCopilotService).to have_received(:new).with(account: account)
    expect(Ramon::NightCopilotService).to have_received(:new).with(account: other_account)
    expect(described_class.new.queue_name).to eq('scheduled_jobs')
  end

  it 'conta com erro não aborta as demais' do
    healthy = instance_double(Ramon::NightCopilotService, perform: 0)
    allow(Ramon::NightCopilotService).to receive(:new).with(account: account).and_raise(StandardError, 'boom')
    allow(Ramon::NightCopilotService).to receive(:new).with(account: other_account).and_return(healthy)

    expect { described_class.perform_now }.not_to raise_error
    expect(healthy).to have_received(:perform)
  end
end
