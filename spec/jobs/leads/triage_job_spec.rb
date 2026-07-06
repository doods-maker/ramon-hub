require 'rails_helper'

RSpec.describe Leads::TriageJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:lead) { create(:lead, account: account) }
  let(:triage) { lead.lead_triages.create!(account: account, triage_agent: account.triage_agents.first) }

  before do
    ActiveJob::Base.queue_adapter = :test
  end

  after do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  it 'roda o TriageService para a triage' do
    service = instance_double(Leads::TriageService, perform: true)
    expect(Leads::TriageService).to receive(:new).with(triage).and_return(service)
    described_class.perform_now(triage.id)
  end

  it 'descarta silenciosamente se a triage sumiu' do
    expect { described_class.perform_now(0) }.not_to raise_error
  end

  it 'configura retry para TransientError do LlmClient' do
    handlers = described_class.rescue_handlers.map(&:first)
    expect(handlers).to include('Ramon::LlmClient::TransientError')
  end

  it 'retenta em falha transitoria e marca error ao esgotar as tentativas' do
    service = instance_double(Leads::TriageService)
    allow(Leads::TriageService).to receive(:new).with(triage).and_return(service)
    allow(service).to receive(:perform).and_raise(Ramon::LlmClient::TransientError, 'rate limited')

    perform_enqueued_jobs { described_class.perform_later(triage.id) }

    expect(service).to have_received(:perform).exactly(3).times
    expect(triage.reload.status).to eq('error')
    expect(triage.error_message).to include('rate limited')
  end
end
