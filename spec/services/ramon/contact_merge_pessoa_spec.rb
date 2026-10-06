require 'rails_helper'

RSpec.describe Ramon::ContactMergePessoa do
  subject(:mesclar) { ContactMergeAction.new(account: account, base_contact: base, mergee_contact: mergee).perform }

  let(:account) { create(:account) }
  let(:base) { create(:contact, account: account, sexo: 'F') }
  let(:mergee) { create(:contact, account: account, cpf: '52998224725', data_nascimento: Date.new(1970, 5, 2), sexo: 'M') }

  it 'leva os leads do contato que sai para o contato que fica' do
    lead = create(:lead, account: account, contact: mergee)
    mesclar
    expect(lead.reload.contact_id).to eq(base.id)
  end

  it 'traz CPF e nascimento do contato que sai, com preferência do base', :aggregate_failures do
    mesclar
    base.reload
    expect(base.cpf).to eq('52998224725')
    expect(base.data_nascimento).to eq(Date.new(1970, 5, 2))
    expect(base.sexo).to eq('F')
  end

  it 'mantém o CPF do base quando os dois têm' do
    base.update!(cpf: '11144477735')
    mesclar
    expect(base.reload.cpf).to eq('11144477735')
  end
end
