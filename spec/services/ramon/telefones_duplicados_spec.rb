require 'rails_helper'

RSpec.describe Ramon::TelefonesDuplicados do
  let(:account) { create(:account) }
  let!(:com_nove) { create(:contact, account: account, phone_number: '+5548991203381') }
  let!(:sem_nove) { create(:contact, account: account, phone_number: '+554891203381') }

  before do
    create(:contact, account: account, phone_number: '+5548999990000')
    create(:contact, account: account, phone_number: '+14155552671')
  end

  it 'agrupa o mesmo celular em grafias diferentes e ignora os únicos' do
    expect(described_class.new(account).grupos.map { |grupo| grupo.map(&:id) }).to contain_exactly(
      contain_exactly(com_nove.id, sem_nove.id)
    )
  end

  it 'não altera nenhum contato' do
    expect { described_class.new(account).grupos }.not_to(change { account.contacts.order(:id).pluck(:phone_number) })
  end
end
