require 'rails_helper'

RSpec.describe Contacts::BulkDeleteService do
  subject(:service) { described_class.new(account: account, contact_ids: contact_ids) }

  let(:account) { create(:account) }
  let!(:contact_one) { create(:contact, account: account) }
  let!(:contact_two) { create(:contact, account: account) }
  let(:contact_ids) { [contact_one.id, contact_two.id] }

  describe '#perform' do
    # FORK(ramon/LGPD): excluir em massa anonimiza (preserva conversas e estatísticas).
    it 'anonymizes the provided contacts instead of destroying them', :aggregate_failures do
      expect { service.perform }.not_to change(Contact, :count)
      expect(contact_one.reload.name).to eq("Titular anonimizado ##{contact_one.id}")
      expect(contact_two.reload.email).to be_nil
    end

    # FORK(ramon/LGPD): cliente com contrato não é eliminado; o lote segue com os demais.
    it 'skips the contact that is a client and anonymizes the others', :aggregate_failures do
      contact_one.update!(email: 'cliente@exemplo.com')
      create(:lead, account: account, lead_stage: account.lead_stages.find_by(is_won: true), contact: contact_one)

      service.perform

      expect(contact_one.reload).to have_attributes(email: 'cliente@exemplo.com')
      expect(contact_one.name).not_to include('anonimizado')
      expect(contact_two.reload.name).to eq("Titular anonimizado ##{contact_two.id}")
    end

    it 'returns when no contact ids are provided' do
      empty_service = described_class.new(account: account, contact_ids: [])

      expect { empty_service.perform }.not_to change(Contact, :count)
    end
  end
end
