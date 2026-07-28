require 'rails_helper'

RSpec.describe Ramon::ReuniaoAtaJob do
  let(:reuniao) { create(:reuniao) }

  it 'runs the service' do
    service = instance_double(Ramon::ReuniaoAtaService, perform: true)
    allow(Ramon::ReuniaoAtaService).to receive(:new).with(reuniao).and_return(service)
    described_class.perform_now(reuniao.id)
    expect(service).to have_received(:perform)
  end

  it 'marks erro on permanent failure' do
    allow(Ramon::ReuniaoAtaService).to receive(:new).and_raise(StandardError, 'boom')
    described_class.perform_now(reuniao.id)
    expect(reuniao.reload).to have_attributes(status: 'erro', erro: 'boom')
  end

  it 'is a no-op when reuniao is gone' do
    expect { described_class.perform_now(0) }.not_to raise_error
  end
end
