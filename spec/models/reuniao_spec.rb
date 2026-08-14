require 'rails_helper'

RSpec.describe Reuniao do
  let(:account) { create(:account) }
  let(:lead_stage) { create(:lead_stage, account: account) }
  let(:lead) { create(:lead, account: account, lead_stage: lead_stage) }

  it 'aceita reuniao sem lead (avulsa segue valendo)' do
    reuniao = described_class.create!(account: account, user: create(:user, account: account))
    expect(reuniao.lead).to be_nil
  end

  it 'vincula lead e sobrevive ao delete do lead (nullify)' do
    reuniao = described_class.create!(account: account, user: create(:user, account: account), lead: lead)
    expect(lead.reunioes).to eq([reuniao])
    lead.destroy!
    expect(reuniao.reload.lead_id).to be_nil
  end
end
