require 'rails_helper'

RSpec.describe Ramon::RascunhoCarimbo do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) { create(:user, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:prefixo) { 'RASCUNHO (revisar antes de enviar):' }

  def rascunho(texto)
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing,
                     private: true, sender: assistant, content: "#{prefixo}\n#{texto}")
  end

  def humano(texto)
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing,
                     private: false, sender: agent, content: texto)
  end

  it 'carimba igual quando o humano manda o rascunho como estava' do
    nota = rascunho('Ola Maria, tudo bem? Preciso do seu CNIS.')
    msg = humano("Ola Maria, tudo bem?  Preciso do seu CNIS. ")

    expect(msg.content_attributes['ramon_rascunho_ia']).to include('nota_id' => nota.id, 'desfecho' => 'igual')
  end

  it 'carimba editado quando muda parte e descartado quando escreve do zero' do
    rascunho('Ola Maria, tudo bem? Preciso do seu CNIS e do laudo medico para seguir.')
    expect(humano('Ola Maria, tudo bem? Preciso do seu CNIS e do laudo para seguir com o pedido.')
      .content_attributes.dig('ramon_rascunho_ia', 'desfecho')).to eq('editado')

    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'oi')
    rascunho('Bom dia! Podemos marcar para quinta?')
    expect(humano('Segue o contrato em anexo, qualquer duvida me chama.')
      .content_attributes.dig('ramon_rascunho_ia', 'desfecho')).to eq('descartado')
  end

  it 'nao carimba sem rascunho depois da ultima mensagem do cliente, nem nota privada, nem mensagem do bot' do
    rascunho('x')
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'oi')
    expect(humano('resposta').content_attributes['ramon_rascunho_ia']).to be_nil

    rascunho('y')
    nota = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing,
                            private: true, sender: agent, content: 'nota interna')
    expect(nota.content_attributes['ramon_rascunho_ia']).to be_nil
    bot = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing,
                           sender: assistant, content: 'y')
    expect(bot.content_attributes['ramon_rascunho_ia']).to be_nil
  end
end
