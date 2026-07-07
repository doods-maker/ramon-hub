require 'rails_helper'

RSpec.describe SearchService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }

  def search(query, type: 'Lead')
    described_class.new(current_user: user, current_account: account,
                        search_type: type, params: { q: query }).perform
  end

  it 'acha lead pelo nome do lead, do contato e telefone' do
    contact = create(:contact, account: account, name: 'Maria Oliveira', phone_number: '+5548988887777')
    stage = account.lead_stages.order(:position).first
    lead = create(:lead, account: account, contact: contact, lead_stage: stage, name: 'Auxílio Maria')

    expect(search('Auxílio Maria')[:leads]).to include(lead)
    expect(search('Oliveira')[:leads]).to include(lead)
    expect(search('48988887777')[:leads]).to include(lead)
  end

  it 'inclui leads no all e não vaza de outra conta' do
    outra = create(:account)
    create(:lead, account: outra, lead_stage: outra.lead_stages.order(:position).first, name: 'Segredo Alheio')

    result = search('Segredo', type: 'all')
    expect(result).to have_key(:leads)
    expect(result[:leads]).to be_empty
  end
end
