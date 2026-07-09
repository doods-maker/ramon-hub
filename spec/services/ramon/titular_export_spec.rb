require 'rails_helper'

describe Ramon::TitularExport do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, :with_email, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  before do
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox,
                     sender: contact, content: 'Ola, quero saber do meu beneficio')
  end
  let!(:lead) { create(:lead, account: account, contact: contact) }
  let!(:note) { create(:note, contact: contact, account: account, content: 'Nota sobre o titular') }

  let(:payload) { described_class.new(contact).payload }

  it 'includes the contact data and leads' do
    expect(payload[:titular]['name']).to eq(contact.name)
    expect(payload[:titular]['email']).to eq(contact.email)
    expect(payload[:leads].map { |l| l['id'] }).to include(lead.id)
    expect(payload[:leads].first).to have_key(:atividades)
  end

  it 'includes conversations with their messages and the contact notes' do
    conversa = payload[:conversas].first
    expect(conversa[:id]).to eq(conversation.display_id)
    expect(conversa[:mensagens].map { |m| m[:conteudo] }).to include('Ola, quero saber do meu beneficio')
    expect(payload[:notas].map { |n| n[:conteudo] }).to include('Nota sobre o titular')
  end
end
