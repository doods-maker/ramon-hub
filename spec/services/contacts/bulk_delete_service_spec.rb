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

    it 'returns when no contact ids are provided' do
      empty_service = described_class.new(account: account, contact_ids: [])

      expect { empty_service.perform }.not_to change(Contact, :count)
    end
  end
end
