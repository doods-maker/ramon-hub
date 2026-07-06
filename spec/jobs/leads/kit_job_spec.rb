require 'rails_helper'

RSpec.describe Leads::KitJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:lead) { create(:lead, account: account) }
  let(:triage) do
    lead.lead_triages.create!(account: account, triage_agent: account.triage_agents.first,
                              status: 'done', viability: 'alta')
  end

  before do
    ActiveJob::Base.queue_adapter = :test
  end

  after do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  it 'roda o KitService para a triage' do
    service = instance_double(Leads::KitService, perform: true)
    expect(Leads::KitService).to receive(:new).with(triage).and_return(service)
    described_class.perform_now(triage.id)
  end

  it 'descarta silenciosamente se a triage sumiu' do
    expect { described_class.perform_now(0) }.not_to raise_error
  end

  it 'configura retry para TransientError do LlmClient' do
    handlers = described_class.rescue_handlers.map(&:first)
    expect(handlers).to include('Ramon::LlmClient::TransientError')
  end

  it 'retenta em falha transitoria e marca kit_status error ao esgotar as tentativas' do
    service = instance_double(Leads::KitService)
    allow(Leads::KitService).to receive(:new).with(triage).and_return(service)
    allow(service).to receive(:perform).and_raise(Ramon::LlmClient::TransientError, 'timeout')

    perform_enqueued_jobs { described_class.perform_later(triage.id) }

    expect(service).to have_received(:perform).exactly(3).times
    expect(triage.reload.kit_status).to eq('error')
    expect(triage.kit['error']).to include('timeout')
  end
end
