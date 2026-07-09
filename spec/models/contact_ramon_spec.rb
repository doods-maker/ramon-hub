require 'rails_helper'

# Campos de pessoa do fork (Linha da Vida): cpf, data_nascimento, sexo.
RSpec.describe Contact do
  let(:account) { create(:account) }

  it 'normaliza o CPF para 11 dígitos e aceita CPF válido' do
    contact = create(:contact, account: account, cpf: '529.982.247-25')
    expect(contact.reload.cpf).to eq('52998224725')
  end

  it 'rejeita CPF com dígito verificador inválido' do
    contact = build(:contact, account: account, cpf: '52998224724')
    expect(contact).not_to be_valid
  end

  it 'rejeita CPF de dígitos repetidos' do
    contact = build(:contact, account: account, cpf: '111.111.111-11')
    expect(contact).not_to be_valid
  end

  it 'aceita contato sem CPF (nil) e não colide unicidade entre nulos' do
    create(:contact, account: account)
    segundo = build(:contact, account: account)
    expect(segundo).to be_valid
  end

  it 'rejeita CPF duplicado na mesma conta e aceita em outra conta' do
    create(:contact, account: account, cpf: '52998224725')
    dup = build(:contact, account: account, cpf: '529.982.247-25')
    outra = build(:contact, account: create(:account), cpf: '52998224725')
    expect(dup).not_to be_valid
    expect(outra).to be_valid
  end

  it 'valida sexo em M/F e aceita nil' do
    expect(build(:contact, account: account, sexo: 'M')).to be_valid
    expect(build(:contact, account: account, sexo: nil)).to be_valid
    expect(build(:contact, account: account, sexo: 'X')).not_to be_valid
  end

  it 'tem N leads (has_many) e anula contact_id ao destruir a pessoa' do
    contact = create(:contact, account: account)
    lead = create(:lead, account: account, contact: contact,
                         lead_stage: account.lead_stages.order(:position).first)
    expect(contact.leads).to contain_exactly(lead)
    contact.destroy!
    expect(lead.reload.contact_id).to be_nil
  end
end
