require 'rails_helper'

RSpec.describe Ramon::MetasDoModelo do
  let(:account) { create(:account) }
  let(:mensal) do
    [{ mes: 'Out/26', contratos: 13, agendadas: 40, realizadas: 30, anuncio: 3250, custo_area: 9000, cac: 999, saldo_acumulado: -1 },
     { mes: 'Jan/27', contratos: 25, agendadas: 70, realizadas: 52, anuncio: 6000, custo_area: 20_000, cac: 800 }].to_json
  end

  it 'grava as métricas por mês e ignora as colunas que não são meta' do
    expect(described_class.importar(account, mensal)).to eq(2)

    metas = MarketingMeta.where(account: account)
    expect(metas.count).to eq(12)
    expect(metas.find_by!(mes: Date.new(2026, 10, 1), metrica: 'gasto_anuncio').valor).to eq(3250)
    expect(metas.find_by!(mes: Date.new(2027, 1, 1), metrica: 'reunioes_realizadas').valor).to eq(52)
  end

  it 'subir de novo substitui todas as metas' do
    described_class.importar(account, mensal)
    described_class.importar(account, [{ mes: 'Nov/26', contratos: 15 }].to_json)

    expect(MarketingMeta.where(account: account).pluck(:mes, :metrica)).to eq([[Date.new(2026, 11, 1), 'contratos']])
  end

  it 'arquivo errado não apaga as metas atuais' do
    described_class.importar(account, mensal)
    expect { described_class.importar(account, '{"x":1}') }.to raise_error(described_class::Erro)
    expect { described_class.importar(account, [{ mes: 'Xyz/26', contratos: 1 }].to_json) }.to raise_error(described_class::Erro, /mês inválido/)
    expect { described_class.importar(account, [{ mes: 'Nov/26', contratos: 1 }, { mes: 'Nov/26', contratos: 2 }].to_json) }
      .to raise_error(described_class::Erro, /repetido/)
    expect { described_class.importar(account, [{ mes: 'Nov/26', contratos: 'x' }].to_json) }.to raise_error(described_class::Erro, /não é número/)
    expect(MarketingMeta.where(account: account).count).to eq(12)
  end

  it 'meta editada à mão: pede confirmação antes de desfazer, e mantém o liga/desliga' do
    described_class.importar(account, mensal)
    MarketingMeta.where(account: account).update_all(ativa: true) # rubocop:disable Rails/SkipsModelValidations
    MarketingMeta.where(account: account).first.update!(valor: 1, editada_em: Time.current)

    expect { described_class.importar(account, mensal) }
      .to raise_error(described_class::PrecisaConfirmar) { |e| expect(e.editadas).to eq(1) }
    described_class.importar(account, mensal, confirmar: true)

    metas = MarketingMeta.where(account: account)
    expect(metas.where.not(editada_em: nil)).to be_empty
    expect(metas.pluck(:ativa).uniq).to eq([true])
  end
end
