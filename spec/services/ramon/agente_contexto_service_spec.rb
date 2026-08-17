require 'rails_helper'

RSpec.describe Ramon::AgenteContextoService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria', additional_attributes: { 'city' => 'Tubarão' }) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  it 'monta mensagens em ordem cronológica, com papel de cada uma, e o contato' do
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming, content: 'oi')
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing,
                     sender: create(:user, account: account), content: 'bom dia')
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, private: true,
                     sender: create(:user, account: account), content: 'nota interna')

    payload = described_class.new(conversation).perform

    expect(payload[:conversa][:mensagens].map { |m| m[:texto] }).to eq(['oi', 'bom dia', 'nota interna'])
    expect(payload[:conversa][:mensagens].map { |m| m[:de] }).to eq(%w[lead atendente nota])
    expect(payload[:contato]).to include(nome: 'Maria', cidade: 'Tubarão')
    expect(payload[:lead]).to be_nil
  end

  it 'inclui o dossiê e o id do lead da conversa' do
    lead = create(:lead, account: account, contact: contact, conversation: conversation)

    payload = described_class.new(conversation).perform

    expect(payload[:lead_id]).to eq(lead.id)
    expect(payload[:lead]).to include(:pessoa, :timeline)
  end
end
