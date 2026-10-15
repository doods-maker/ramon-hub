require 'rails_helper'

RSpec.describe Ramon::Honorario do
  let(:account) { create(:account) }

  def tese(**attrs)
    create(:thesis, account: account, name: "Tese #{SecureRandom.hex(3)}", honorario_na_tabela: true, **attrs)
  end

  describe '.calcular' do
    it 'soma o percentual dos atrasados e 3 benefícios' do
      t = tese(honorario_percentual: 30, honorario_n_mensalidades: 3)
      res = described_class.calcular(t, atrasados: 10_000, mensal: 2000)
      expect(res[:valor]).to eq('9000.00') # 3000 + 3 × 2000
    end

    it 'usa o salário mínimo no "3" quando o benefício é menor que ele' do
      t = tese(honorario_percentual: 30, honorario_n_mensalidades: 3)
      res = described_class.calcular(t, atrasados: 10_000, mensal: 800)
      expect(res[:valor]).to eq('7863.00') # 3000 + 3 × 1621
    end

    it 'vale o mínimo quando ele é maior que a fórmula' do
      t = tese(honorario_percentual: 30, honorario_minimo_qtd: 1, honorario_minimo_base: 'sb')
      res = described_class.calcular(t, atrasados: 1000, mensal: 2000)
      expect(res[:valor]).to eq('2000.00') # 300 < 1 × 2000
    end

    it 'mínimo em salários mínimos' do
      t = tese(honorario_percentual: 30, honorario_n_mensalidades: 3, honorario_minimo_qtd: 3, honorario_minimo_base: 'sm')
      res = described_class.calcular(t, atrasados: 0, mensal: 500)
      expect(res[:valor]).to eq('4863.00') # 3 × 1621 (fórmula = mínimo)
    end

    it 'tese fora da tabela não calcula e explica o motivo' do
      t = create(:thesis, account: account, honorario_percentual: 30, honorario_n_mensalidades: 3)
      res = described_class.calcular(t, atrasados: 10_000, mensal: 2000)
      expect(res).to eq(valor: nil, motivo: described_class::FORA_DA_TABELA)
    end

    it 'tese na tabela sem percentual nem mensalidades é sem configuração' do
      res = described_class.calcular(tese, atrasados: 1, mensal: 1)
      expect(res).to eq(valor: nil, motivo: described_class::SEM_CONFIG)
    end

    it 'sem tese é sem configuração' do
      expect(described_class.calcular(nil, atrasados: 1, mensal: 1)[:motivo]).to eq(described_class::SEM_CONFIG)
    end
  end

  describe '.descricao' do
    it 'auxílio-acidente (online)' do
      t = tese(honorario_percentual: 30, honorario_n_mensalidades: 3, honorario_minimo_qtd: 3, honorario_minimo_base: 'sm')
      expect(described_class.descricao(t)).to eq(
        '30% dos atrasados + 3 benefícios (cada um de pelo menos 1 salário mínimo), mínimo 3 salários mínimos'
      )
    end

    it 'singular quando n = 1' do
      t = tese(honorario_percentual: 30, honorario_n_mensalidades: 1)
      expect(described_class.descricao(t)).to eq('30% dos atrasados + 1 benefício (de pelo menos 1 salário mínimo)')
    end

    it 'só percentual com mínimo de 1 benefício' do
      t = tese(honorario_percentual: 30, honorario_minimo_qtd: 1, honorario_minimo_base: 'sb')
      expect(described_class.descricao(t)).to eq('30% dos atrasados, mínimo 1 benefício')
    end

    it 'percentual fracionado com vírgula, sem mensalidades zeradas' do
      t = tese(honorario_percentual: 12.5, honorario_n_mensalidades: 0)
      expect(described_class.descricao(t)).to eq('12,5% dos atrasados')
    end

    it 'trabalhista: percentual do êxito, não dos atrasados' do
      expect(described_class.descricao(tese(area: 'trabalhista', honorario_percentual: 25))).to eq('25% do que o cliente receber no processo')
    end

    it 'fora da tabela' do
      expect(described_class.descricao(create(:thesis, account: account))).to eq(described_class::FORA_DA_TABELA)
    end

    it 'sem configuração devolve nil' do
      expect(described_class.descricao(tese)).to be_nil
    end
  end

  describe Ramon::SalarioMinimo do
    it 'vale R$ 1.621 em 2026' do
      expect(described_class.vigente(Date.new(2026, 10, 13))).to eq(BigDecimal(1621))
    end
  end
end
