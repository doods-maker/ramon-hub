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

  # O sender Captain::Assistant vive em enterprise/: insert_all evita instanciá-lo (roda no CI FOSS).
  it 'descarta rascunho do Copiloto mas mantém nota do AgentBot' do
    # rubocop:disable Rails/SkipsModelValidations
    Message.insert_all([{ account_id: account.id, inbox_id: inbox.id, conversation_id: conversation.id,
                          message_type: 1, private: true, sender_type: 'Captain::Assistant', sender_id: 1,
                          content: 'rascunho do copiloto', created_at: Time.current, updated_at: Time.current }])
    # rubocop:enable Rails/SkipsModelValidations
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, private: true,
                     sender: create(:agent_bot, account: account, name: 'Claude'), content: 'nota do Claude')

    textos = described_class.new(conversation).perform[:conversa][:mensagens].map { |m| m[:texto] }

    expect(textos).to eq(['nota do Claude'])
  end

  it 'inclui o dossiê e o id do lead da conversa' do
    lead = create(:lead, account: account, contact: contact, conversation: conversation)

    payload = described_class.new(conversation).perform

    expect(payload[:lead_id]).to eq(lead.id)
    expect(payload[:lead]).to include(:pessoa, :timeline)
  end
end
