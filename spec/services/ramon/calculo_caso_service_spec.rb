require 'rails_helper'

RSpec.describe Ramon::CalculoCasoService do
  let(:account) { create(:account) }
  let(:stage) { account.lead_stages.order(:position).first }

  def perform(params)
    described_class.new(account: account, params: params).perform
  end

  it 'reusa contato por CPF e devolve leads existentes sem criar caso' do
    contact = create(:contact, account: account, cpf: '52998224725')
    lead = create(:lead, account: account, lead_stage: stage, contact: contact)
    result = perform(nome: 'Fulano', cpf: '529.982.247-25')
    expect(result[:contact]).to eq(contact)
    expect(result[:leads]).to contain_exactly(lead)
    expect(account.leads.reorder(nil).count).to eq(1)
  end

  it 'reusa contato por telefone quando não há CPF' do
    contact = create(:contact, account: account, phone_number: '+5548999887766')
    result = perform(nome: 'Fulano', telefone: '(48) 99988-7766')
    expect(result[:contact]).to eq(contact)
  end

  it 'cria contato + caso de cálculo oculto quando pessoa não existe' do
    result = perform(nome: 'Nova Pessoa', cpf: '529.982.247-25', nascimento: '1980-05-10')
    contact = result[:contact]
    expect(contact.cpf).to eq('52998224725')
    expect(contact.data_nascimento).to eq(Date.new(1980, 5, 10))
    caso = result[:leads].sole
    expect(caso.source).to eq(Lead::FONTE_CALCULO)
    expect(caso.lead_stage).to eq(stage)
    expect(account.leads.funil).not_to include(caso)
  end

  it 'CPF inválido não derruba: cria contato sem CPF' do
    result = perform(nome: 'Nova Pessoa', cpf: '111.111.111-11')
    expect(result[:contact].cpf).to be_nil
    expect(result[:leads].sole.source).to eq(Lead::FONTE_CALCULO)
  end

  it 'preenche só campo vazio de contato reusado (não sobrescreve)' do
    contact = create(:contact, account: account, cpf: '52998224725',
                               data_nascimento: Date.new(1970, 1, 1))
    perform(nome: 'Outro Nome', cpf: '52998224725', nascimento: '1980-05-10')
    expect(contact.reload.data_nascimento).to eq(Date.new(1970, 1, 1))
    expect(contact.name).not_to eq('Outro Nome')
  end

  it 'preenche nascimento vazio de contato reusado' do
    contact = create(:contact, account: account, cpf: '52998224725', data_nascimento: nil)
    perform(nome: 'Fulano', cpf: '52998224725', nascimento: '1980-05-10')
    expect(contact.reload.data_nascimento).to eq(Date.new(1980, 5, 10))
  end

  it 'e-mail já usado por outro contato não derruba: cria contato sem e-mail' do
    create(:contact, account: account, email: 'familia@exemplo.com')
    result = perform(nome: 'Cônjuge', cpf: '529.982.247-25', email: 'familia@exemplo.com')
    expect(result[:contact].email).to be_nil
    expect(result[:contact].cpf).to eq('52998224725')
    expect(result[:leads].sole.source).to eq(Lead::FONTE_CALCULO)
  end

  it 'CPF inválido não fica sujo em memória no contato reusado e o resto ainda salva' do
    reusado = create(:contact, account: account, phone_number: '+5548999887766', cpf: nil)
    result = perform(nome: 'Fulano', telefone: '48999887766', cpf: '111.111.111-11',
                     nascimento: '1980-05-10')
    expect(result[:contact]).to eq(reusado)
    expect(result[:contact].cpf).to be_nil
    expect(reusado.reload.data_nascimento).to eq(Date.new(1980, 5, 10))
  end

  it 'com contact_id cria caso pro contato do hub sem lead' do
    contact = create(:contact, account: account)
    result = perform(contact_id: contact.id)
    expect(result[:contact]).to eq(contact)
    expect(result[:leads].sole.source).to eq(Lead::FONTE_CALCULO)
  end
end
