require 'rails_helper'

# Consentimento LGPD manual: o painel do lead marca/desmarca via contacts#update
# com custom_attributes.consent_marketing (o core faz merge, não replace).
RSpec.describe 'Contact marketing consent (LGPD)', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, custom_attributes: { 'outra_chave' => 'fica' }) }

  def put_consent(granted)
    put "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
        params: {
          custom_attributes: {
            consent_marketing: { granted: granted, at: '2026-07-09T10:00:00Z', source: 'manual' }
          }
        },
        headers: agent.create_new_auth_token,
        as: :json
  end

  it 'marca o consentimento manual e preserva os demais custom_attributes' do
    put_consent(true)

    expect(response).to have_http_status(:success)
    consent = contact.reload.custom_attributes['consent_marketing']
    expect(consent).to eq('granted' => true, 'at' => '2026-07-09T10:00:00Z', 'source' => 'manual')
    expect(contact.custom_attributes['outra_chave']).to eq 'fica'
  end

  it 'desmarca (revoga) o consentimento manual' do
    contact.update!(custom_attributes: contact.custom_attributes.merge(
      'consent_marketing' => { 'granted' => true, 'at' => '2026-01-01T00:00:00Z', 'source' => 'lp:auxilio-acidente' }
    ))

    put_consent(false)

    expect(contact.reload.custom_attributes.dig('consent_marketing', 'granted')).to be false
    expect(contact.custom_attributes.dig('consent_marketing', 'source')).to eq 'manual'
  end
end
