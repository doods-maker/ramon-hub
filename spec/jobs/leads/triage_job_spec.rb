require 'rails_helper'

RSpec.describe Leads::TriageJob do
  let(:account) { create(:account) }
  let(:lead) { create(:lead, account: account) }
  let(:triage) { lead.lead_triages.create!(account: account, triage_agent: account.triage_agents.first) }

  it 'roda o TriageService para a triage' do
    service = instance_double(Leads::TriageService, perform: true)
    expect(Leads::TriageService).to receive(:new).with(triage).and_return(service)
    described_class.perform_now(triage.id)
  end

  it 'descarta silenciosamente se a triage sumiu' do
    expect { described_class.perform_now(0) }.not_to raise_error
  end
end
