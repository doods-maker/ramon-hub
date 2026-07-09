require 'rails_helper'

describe Ramon::ContactAnonymizer do
  let(:account) { create(:account) }
  let(:contact) do
    create(:contact, account: account, name: 'Joao da Silva', email: 'contato@exemplo.com',
                     phone_number: '+5548999998888', cpf: '52998224725',
                     custom_attributes: { 'apelido' => 'Joaozinho' })
  end
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:message) do
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox,
                     sender: contact, content: 'Sou o Joao, CPF 529.982.247-25, escreve pra contato@exemplo.com')
  end
  let!(:note) { create(:note, contact: contact, account: account, content: 'Cliente confirmou o CPF 529.982.247-25') }

  def perform
    described_class.new(contact).perform
  end

  it 'anonymizes the contact identity fields' do
    perform
    expect(contact.reload.name).to eq("Titular anonimizado ##{contact.id}")
    expect(contact.email).to be_nil
    expect(contact.phone_number).to be_nil
    expect(contact.cpf).to be_nil
    expect(contact.custom_attributes).to eq({})
  end

  it 'redacts PII from messages while preserving the conversation' do
    perform
    expect(message.reload.content).to include('[nome]')
    expect(message.content).to include('[cpf]')
    expect(message.content).not_to include('529.982.247-25')
    expect(message.content).not_to include('contato@exemplo.com')
    expect(conversation.reload).to be_present
  end

  it 'redacts PII from contact notes' do
    perform
    expect(note.reload.content).to include('[cpf]')
    expect(note.content).not_to include('529.982.247-25')
  end

  it 'purges the audit trail so old PII values do not survive in audits' do
    contact.update!(phone_number: '+5548988887777')
    expect(Audited.audit_class.where(auditable: contact)).to be_present

    perform
    expect(Audited.audit_class.where(auditable: contact)).to be_empty
  end
end
