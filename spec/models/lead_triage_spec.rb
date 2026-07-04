require 'rails_helper'

RSpec.describe LeadTriage do
  let(:account) { create(:account) }
  let(:lead) { create(:lead, account: account) }
  let(:agent) { account.triage_agents.create!(name: 'X', system_prompt: 'p') }

  it 'nasce pending e valida status/viability' do
    triage = lead.lead_triages.create!(account: account, triage_agent: agent)
    expect(triage.status).to eq('pending')
    expect(triage.viability).to be_nil
  end

  it 'rejeita viability fora de alta|media|baixa' do
    triage = lead.lead_triages.new(account: account, triage_agent: agent, viability: 'high')
    expect(triage).not_to be_valid
  end

  it 'lead.latest_triage retorna a triagem mais recente por id' do
    old = lead.lead_triages.create!(account: account, triage_agent: agent)
    newer = lead.lead_triages.create!(account: account, triage_agent: agent)
    expect(lead.reload.latest_triage).to eq(newer)
    expect(lead.latest_triage).not_to eq(old)
  end

  it 'redispara o broadcast do lead ao mudar de status' do
    triage = lead.lead_triages.create!(account: account, triage_agent: agent)
    expect(Rails.configuration.dispatcher).to receive(:dispatch)
      .with(Events::Types::LEAD_UPDATED, anything, lead: lead)
    triage.update!(status: 'done', result: 'ok')
  end
end
