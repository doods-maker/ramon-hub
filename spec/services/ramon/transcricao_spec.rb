require 'rails_helper'

RSpec.describe Ramon::Transcricao do
  let(:account) { create(:account) }
  let(:conversa) { create(:conversation, account: account) }

  def msg(tipo, content, private: false)
    create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: tipo, content: content, private: private)
  end

  it 'monta as linhas Cliente/Atendimento e ignora notas privadas' do
    msg(:incoming, 'Oi, preciso de ajuda')
    msg(:outgoing, 'Claro, me conte')
    msg(:outgoing, 'nota interna', private: true)

    expect(described_class.de(conversa)).to eq("Conversa (WhatsApp/chat):\nCliente: Oi, preciso de ajuda\nAtendimento: Claro, me conte")
  end

  it 'respeita o limite pegando as últimas mensagens' do
    msg(:incoming, 'primeira')
    msg(:incoming, 'segunda')

    expect(described_class.de(conversa, limite: 1)).to eq("Conversa (WhatsApp/chat):\nCliente: segunda")
  end

  it 'com_hora prefixa cada linha com dia/hora de São Paulo' do
    travel_to(Time.zone.parse('2026-10-16 14:30:00 -03:00')) { msg(:incoming, 'Oi') }

    expect(described_class.de(conversa, com_hora: true)).to eq("Conversa (WhatsApp/chat):\n[16/10 14:30] Cliente: Oi")
  end

  it 'sem conversa ou sem mensagens devolve nil' do
    expect(described_class.de(nil)).to be_nil
    expect(described_class.de(conversa)).to be_nil
  end
end
