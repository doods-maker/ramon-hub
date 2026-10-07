require 'rails_helper'

RSpec.describe Ramon::FaqDeConversa do
  let(:account) { create(:account) }
  let(:contato) { create(:contact, account: account, name: 'Maria Souza', email: 'maria@exemplo.com') }
  let(:conversa) { create(:conversation, account: account, contact: contato) }

  def msg(tipo, texto, privada: false)
    create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: tipo,
                     content: texto, private: privada)
  end

  describe '.de_mensagem' do
    it 'junta as bolhas do lead desde a última resposta enviada e mascara os dados pessoais', :aggregate_failures do
      msg(:incoming, 'Oi, quanto custa?')
      msg(:outgoing, 'Você só paga se ganhar.')
      msg(:incoming, 'Sou a Maria Souza, CPF 123.456.789-09')
      msg(:outgoing, 'Anotei aqui.', privada: true)
      msg(:incoming, 'Precisa pagar a perícia?')
      resposta = msg(:outgoing, 'Maria, a perícia do INSS é gratuita.')

      faq = described_class.de_mensagem(resposta)

      expect(faq[:question]).to eq("Sou a [nome], CPF [cpf]\nPrecisa pagar a perícia?")
      expect(faq[:answer]).to eq('[nome], a perícia do INSS é gratuita.')
    end

    it 'a resposta automática de bot no meio não corta a pergunta do lead' do
      msg(:incoming, 'Quanto custa?')
      create(:message, :bot_message, account: account, conversation: conversa, inbox: conversa.inbox, content: 'Já te respondo')
      resposta = msg(:outgoing, 'Você só paga se ganhar.')

      expect(described_class.de_mensagem(resposta)[:question]).to eq('Quanto custa?')
    end

    it 'mascara também o nome do lead (diferente do contato)' do
      create(:lead, account: account, conversation_id: conversa.id, name: 'Joana Dores')
      msg(:incoming, 'A Joana pode ir no meu lugar?')
      resposta = msg(:outgoing, 'Pode sim.')

      expect(described_class.de_mensagem(resposta)[:question]).to eq('A [nome] pode ir no meu lugar?')
    end

    it 'corta pergunta muito longa' do
      msg(:incoming, 'a' * 900)
      resposta = msg(:outgoing, 'Certo.')

      expect(described_class.de_mensagem(resposta)[:question].length).to eq(described_class::LIMITE_PERGUNTA)
    end

    it 'recusa nota privada, mensagem do lead e resposta sem pergunta antes', :aggregate_failures do
      nota = msg(:outgoing, 'nota interna', privada: true)
      expect { described_class.de_mensagem(nota) }.to raise_error(described_class::Recusa, 'SEM_RESPOSTA')

      do_lead = msg(:incoming, 'Oi')
      expect { described_class.de_mensagem(do_lead) }.to raise_error(described_class::Recusa, 'SEM_RESPOSTA')

      msg(:outgoing, 'Olá!')
      sozinha = msg(:outgoing, 'Posso ajudar?')
      expect { described_class.de_mensagem(sozinha) }.to raise_error(described_class::Recusa, 'SEM_PERGUNTA')
    end
  end

  describe '.texto' do
    it 'manda o fim da conversa sem notas privadas e com os dados mascarados', :aggregate_failures do
      msg(:incoming, 'Meu telefone é (48) 99999-8888, sou a Maria Souza')
      msg(:outgoing, 'RASCUNHO segredo interno', privada: true)

      texto = described_class.texto(conversa)

      expect(texto).to include('[telefone]', '[nome]')
      expect(texto).not_to include('99999')
      expect(texto).not_to include('Maria')
      expect(texto).not_to include('segredo')
    end

    it 'não leva cabeçalho nem atributos da conversa (só mensagens)', :aggregate_failures do
      definicao = create(:custom_attribute_definition, account: account, attribute_model: :conversation_attribute)
      conversa.update!(custom_attributes: { definicao.attribute_key => 'VALOR_SECRETO_XYZ' })
      msg(:incoming, 'Oi, tenho uma dúvida')

      texto = described_class.texto(conversa)

      expect(texto).to eq("User: Oi, tenho uma dúvida\n")
      expect(texto).not_to include('VALOR_SECRETO_XYZ')
    end

    it 'mascara CPF e telefone em vários formatos', :aggregate_failures do
      ['123.456.789-09', '12345678909', '(48) 99999-8888', '48 99999-8888', '99999-8888', '+55 48 99999-8888'].each do |dado|
        msg(:incoming, "meu dado: #{dado}")
      end

      texto = described_class.texto(conversa)

      expect(texto).not_to match(/\d{4}/)
      expect(texto.scan('[cpf]').size + texto.scan('[telefone]').size).to eq(6)
    end

    it 'mensagem mais nova maior que o limite é cortada (fim), não vira texto vazio', :aggregate_failures do
      msg(:incoming, 'a' * 9_000)

      texto = described_class.texto(conversa)

      expect(texto.length).to eq(described_class::LIMITE_CONVERSA)
      expect(texto).to end_with("aaa
")
    end

    it 'corta no limite: o começo de uma conversa longa não vai', :aggregate_failures do
      msg(:incoming, 'a' * 5_000)
      msg(:incoming, 'b' * 5_000)

      texto = described_class.texto(conversa)

      expect(texto).to include('b' * 100)
      expect(texto).not_to include('a' * 100)
    end
  end

  describe '.pausada?' do
    it 'só pausa com teto definido e o gasto do dia no teto', :aggregate_failures do
      expect(described_class.pausada?(account)).to be(false)

      account.update!(settings: (account.settings || {}).merge(Ramon::IaGastoAlerta::CHAVE_TETO => '1.00'))
      LlmChamada.create!(account: account, funcao: 'atendimento', custo_usd: 0.5)
      expect(described_class.pausada?(account)).to be(false)

      LlmChamada.create!(account: account, funcao: 'atendimento', custo_usd: 0.5)
      expect(described_class.pausada?(account)).to be(true)
    end
  end

  it 'o prompt traz a regra do honorário e proíbe dado pessoal', :aggregate_failures do
    expect(described_class::PROMPT).to include('30% dos atrasados + 3 parcelas do benefício')
    expect(described_class::PROMPT).to include('sem nome, CPF')
  end
end
