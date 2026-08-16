require 'rails_helper'

RSpec.describe Ramon::Honorario do
  let(:account) { create(:account) }

  it 'aplica percentual dos atrasados + N mensalidades' do
    tese = create(:thesis, account: account, name: 'Auxílio', honorario_percentual: 30, honorario_n_mensalidades: 3)

    resultado = described_class.calcular(tese, atrasados: BigDecimal('10000'), mensal: BigDecimal('1500'))

    expect(resultado).to eq(valor: '7500.00', percentual: 30.0, n_mensalidades: 3, tese: 'Auxílio')
  end

  it 'trata percentual ou mensalidades ausentes como zero quando o outro esta configurado' do
    tese = create(:thesis, account: account, honorario_percentual: nil, honorario_n_mensalidades: 2)

    expect(described_class.calcular(tese, atrasados: 10_000, mensal: 1000.5)[:valor]).to eq('2001.00')
  end

  it 'devolve motivo quando a tese nao tem honorario configurado' do
    tese = create(:thesis, account: account)

    expect(described_class.calcular(tese, atrasados: 1, mensal: 1)).to eq(valor: nil, motivo: described_class::SEM_CONFIG)
  end

  it 'devolve motivo quando nao ha tese' do
    expect(described_class.calcular(nil, atrasados: 1, mensal: 1)[:valor]).to be_nil
  end
end
