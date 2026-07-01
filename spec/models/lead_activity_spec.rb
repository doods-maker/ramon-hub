require 'rails_helper'

RSpec.describe LeadActivity do
  let(:account) { create(:account) }
  let(:lead) { create(:lead, account: account) }

  it 'is valid with a lead, kind and no user (system)' do
    activity = described_class.new(account: account, lead: lead, kind: 'created')
    expect(activity).to be_valid
    expect(activity.user).to be_nil
  end

  it 'requires a kind' do
    activity = described_class.new(account: account, lead: lead, kind: nil)
    expect(activity).not_to be_valid
  end

  it 'belongs to an optional user (author)' do
    user = create(:user, account: account)
    activity = described_class.create!(account: account, lead: lead, user: user,
                                       kind: 'stage_changed', from_value: 'Novo', to_value: 'Qualificação')
    expect(activity.reload.user).to eq(user)
  end
end
