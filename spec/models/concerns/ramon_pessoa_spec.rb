require 'rails_helper'

# Cobertura do audited adicionado via RamonPessoa (LGPD — trilha de PII do titular).
describe RamonPessoa do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  it 'records an audit when a PII column changes' do
    expect { contact.update!(phone_number: '+5548999998888') }.to change { contact.audits.count }.by(1)
    expect(contact.audits.last.audited_changes).to have_key('phone_number')
  end

  it 'does not record audits for non-PII columns' do
    contact
    expect { contact.update!(last_activity_at: Time.zone.now) }.not_to(change { contact.audits.count })
  end
end
