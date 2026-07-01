require 'rails_helper'

RSpec.describe LeadNote do
  let(:account) { create(:account) }
  let(:lead) { create(:lead, account: account) }

  it 'is valid with a lead and body' do
    expect(described_class.new(account: account, lead: lead, body: 'oi')).to be_valid
  end

  it 'requires a body' do
    expect(described_class.new(account: account, lead: lead, body: nil)).not_to be_valid
  end

  it 'belongs to an optional author' do
    user = create(:user, account: account)
    note = described_class.create!(account: account, lead: lead, user: user, body: 'x')
    expect(note.reload.user).to eq(user)
  end
end
