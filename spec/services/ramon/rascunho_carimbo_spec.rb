require 'rails_helper'

# Cobertura pura do hook (sem Captain::Assistant) — roda tambem no CI FOSS.
RSpec.describe Ramon::RascunhoCarimbo do
  describe '.candidata?' do
    it 'aceita mensagem publica outgoing do humano e recusa a privada' do
      publica = Message.new(message_type: :outgoing, private: false, sender_type: 'User', content: 'oi')
      privada = Message.new(message_type: :outgoing, private: true, sender_type: 'User', content: 'oi')

      expect(described_class.candidata?(publica)).to be(true)
      expect(described_class.candidata?(privada)).to be(false)
    end
  end

  describe '.normal' do
    it 'baixa a caixa e colapsa espacos' do
      expect(described_class.normal("  Ola   Maria,  tudo bem?  \n")).to eq('ola maria, tudo bem?')
    end
  end

  describe '.similaridade' do
    it 'calcula jaccard das palavras (>=3 letras)' do
      expect(described_class.similaridade('preciso do cnis e do laudo', 'preciso do cnis e do documento')).to be_within(0.01).of(0.5)
    end
  end

  # A mensagem do Assistente (Captain::Assistant, enterprise/) e inserida por
  # insert_all, sem instanciar o sender — assim o fluxo roda no CI FOSS.
  describe 'carimbo completo' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:agent) { create(:user, account: account) }
    let(:prefixo) { 'RASCUNHO (revisar antes de enviar):' }

    def do_assistente(texto, privada:)
      id = Message.insert_all([{ account_id: account.id, inbox_id: inbox.id, conversation_id: conversation.id,
                                 message_type: 1, private: privada, sender_type: 'Captain::Assistant', sender_id: 1,
                                 content: texto, created_at: Time.current, updated_at: Time.current }],
                              returning: :id).first['id']
      Message.find(id)
    end

    def rascunho(texto)
      do_assistente("#{prefixo}\n#{texto}", privada: true)
    end

    def humano(texto)
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing,
                       private: false, sender: agent, content: texto)
    end

    it 'carimba igual quando o humano manda o rascunho como estava' do
      nota = rascunho('Ola Maria, tudo bem? Preciso do seu CNIS.')
      msg = humano('Ola Maria, tudo bem?  Preciso do seu CNIS. ')

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

    it 'usa a nota mais nova quando ha duas rascunho depois da ultima mensagem do cliente' do
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'oi')
      rascunho('Bom dia! Podemos marcar para quinta?')
      nota_nova = rascunho('Boa tarde! Ficou pronto o documento?')

      msg = humano('Boa tarde! Ficou pronto o documento?')

      expect(msg.content_attributes['ramon_rascunho_ia']).to include('nota_id' => nota_nova.id, 'desfecho' => 'igual')
    end

    it 'consome o rascunho na 1a resposta humana e nao carimba a 2a resposta sem novo incoming' do
      rascunho('Ola Maria, tudo bem?')
      msg_a = humano('Ola Maria, tudo bem?')
      msg_b = humano('Ainda por ai?')

      expect(msg_a.content_attributes['ramon_rascunho_ia']).to include('desfecho' => 'igual')
      expect(msg_b.content_attributes['ramon_rascunho_ia']).to be_nil
    end

    it 'nao carimba sem rascunho depois da ultima mensagem do cliente, nem nota privada, nem mensagem do bot' do
      rascunho('x')
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'oi')
      expect(humano('resposta').content_attributes['ramon_rascunho_ia']).to be_nil

      rascunho('y')
      nota = create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing,
                              private: true, sender: agent, content: 'nota interna')
      expect(nota.content_attributes['ramon_rascunho_ia']).to be_nil
      bot = do_assistente('y', privada: false)
      expect(bot.content_attributes['ramon_rascunho_ia']).to be_nil
    end
  end
end
