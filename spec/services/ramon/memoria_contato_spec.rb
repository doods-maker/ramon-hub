require 'rails_helper'

RSpec.describe Ramon::MemoriaContato do
  let(:account) { create(:account) }
  let(:contato) { create(:contact, account: account, name: 'Maria Souza') }
  let(:conversa) { create(:conversation, account: account, contact: contato) }
  let(:lead) { create(:lead, account: account, conversation: conversa, name: 'Maria Souza') }

  describe '.itens' do
    it 'le a lista do JSON, mesmo com texto em volta' do
      expect(described_class.itens('ok {"memoria": ["Interesse: auxílio-acidente"]} fim')).to eq(['Interesse: auxílio-acidente'])
    end

    it 'JSON quebrado, sem a chave ou nada vira lista vazia', :aggregate_failures do
      expect(described_class.itens('{"memoria": [')).to eq([])
      expect(described_class.itens('{"faqs": []}')).to eq([])
      expect(described_class.itens(nil)).to eq([])
    end
  end

  describe '.gravar!' do
    it 'grava uma nota no lead com os itens, sem os de saude (nome de beneficio nao conta como saude)', :aggregate_failures do
      nota = described_class.gravar!(lead, 482, ['Interesse: auxílio-acidente', 'CID M54, lombalgia', 'Recebeu auxílio-doença (B31) em 2024',
                                                 'Dor na coluna e no ombro', 'Laudo com F32', 'Não sabe ler', 'Trabalha como pedreiro'])

      expect(nota.body).to eq("MEMÓRIA DA IA (conversa #482):\n- Interesse: auxílio-acidente\n- Recebeu auxílio-doença (B31) em 2024\n" \
                              "- Não sabe ler\n- Trabalha como pedreiro")
      expect(nota.user_id).to be_nil
    end

    it 'sem itens, ou so com item de saude, nao grava' do
      expect { described_class.gravar!(lead, 1, ['', 'Tem depressão', 'Fez cirurgia no joelho', 'Tem LER e DORT']) }.not_to change(LeadNote, :count)
    end

    it 'no maximo 6 itens e 1000 caracteres', :aggregate_failures do
      nota = described_class.gravar!(lead, 1, Array.new(9) { |numero| "Fato #{numero} #{'x' * 200}" })

      expect(nota.body.scan(/^- /).size).to be <= 6
      expect(nota.body.length).to be <= 1000
    end
  end

  describe '.texto' do
    it 'leva as memorias anteriores e a conversa mascarada', :aggregate_failures do
      described_class.gravar!(lead, 1, ['Interesse: BPC'])
      create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :incoming,
                       content: 'Sou a Maria Souza, meu CPF é 123.456.789-09')

      texto = described_class.texto(conversa, lead)

      expect(texto).to include('Interesse: BPC')
      expect(texto).not_to include('Maria Souza')
      expect(texto).not_to include('123.456.789-09')
    end
  end

  it 'o prompt proibe saude e documentos' do
    expect(described_class::PROMPT).to include('NUNCA anote').and include('CID').and include('CPF')
  end
end
