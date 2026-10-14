require 'rails_helper'

RSpec.describe Ramon::Roteiro::Resposta do
  def passo(tipo, opcoes: [])
    build(:roteiro_passo, tipo_resposta: tipo, opcoes: opcoes)
  end

  describe '.normalizar' do
    it 'sim_nao, escolha, numero, data e texto' do
      expect(described_class.normalizar(passo('sim_nao'), 'Sim!')).to eq(['sim', nil])
      expect(described_class.normalizar(passo('escolha', opcoes: ['Carteira assinada', 'Autônomo']), 'autonomo'))
        .to eq(['Autônomo', nil])
      expect(described_class.normalizar(passo('numero'), 'R$ 1.200,50')).to eq(['1200.5', nil])
      expect(described_class.normalizar(passo('data'), '12/03/2025')).to eq(['2025-03-12', nil])
      expect(described_class.normalizar(passo('texto'), '  ficou com dor  ')).to eq(['ficou com dor', nil])
    end

    it 'devolve erro sem valor quando o formato não serve' do
      expect(described_class.normalizar(passo('sim_nao'), 'talvez')).to eq([nil, 'Responda sim ou nao.'])
      expect(described_class.normalizar(passo('data'), '31/02/2026').last).to include('AAAA-MM-DD')
      expect(described_class.normalizar(passo('escolha', opcoes: %w[A B]), 'C').last).to include('A | B')
      expect(described_class.normalizar(passo('numero'), 'muito').last).to include('numero')
    end

    it 'vazio = nada' do
      expect(described_class.normalizar(passo('sim_nao'), ' ')).to eq([nil, nil])
    end
  end

  describe '.casa?' do
    it 'valor exato sem acento e caixa, faixa numérica e curinga' do
      expect(described_class.casa?('Não', 'nao')).to be(true)
      expect(described_class.casa?('< 64', '63')).to be(true)
      expect(described_class.casa?('>= 65', '64.9')).to be(false)
      expect(described_class.casa?('> 1,5', '2')).to be(true)
      expect(described_class.casa?('< 64', 'abc')).to be(false)
      expect(described_class.casa?('*', nil)).to be(true)
      expect(described_class.casa?('sim', 'nao')).to be(false)
    end
  end
end
