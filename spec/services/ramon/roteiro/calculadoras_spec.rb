require 'rails_helper'

RSpec.describe Ramon::Roteiro::Calculadoras do
  let(:hoje) { Date.new(2026, 10, 13) }

  def calc(nome, **campos)
    described_class.calcular(nome, campos, hoje: hoje)
  end

  describe 'periodo_de_graca' do
    # último vínculo 10/03/2025: 12 meses → mantém até 15/05/2026; 24 → 15/05/2027; 36 → 15/05/2028
    let(:base) { { ultimo_vinculo: '2025-03-10' } }

    it 'dentro quando tinha vínculo na data do evento' do
      expect(calc('periodo_de_graca', **base, evento: '2025-01-05')[:resultado]).to eq('dentro')
    end

    it 'dentro até o dia 15 do 2º mês depois dos 12 meses (art. 15 §4º)' do
      expect(calc('periodo_de_graca', **base, evento: '2026-05-15')[:resultado]).to eq('dentro')
      expect(calc('periodo_de_graca', **base, evento: '2026-05-16', mais_de_120: 'nao', desemprego: 'nao')[:resultado])
        .to eq('fora')
    end

    it 'faixa de 24 meses: uma extensão basta; sem saber = depende' do
      evento = '2027-01-10'
      expect(calc('periodo_de_graca', **base, evento: evento, mais_de_120: 'sim')[:resultado]).to eq('dentro')
      expect(calc('periodo_de_graca', **base, evento: evento, mais_de_120: 'nao', desemprego: 'sim')[:resultado]).to eq('dentro')
      expect(calc('periodo_de_graca', **base, evento: evento, mais_de_120: 'nao')[:resultado]).to eq('depende')
    end

    it 'faixa de 36 meses: precisa das duas extensões' do
      evento = '2028-01-10'
      expect(calc('periodo_de_graca', **base, evento: evento, mais_de_120: 'sim', desemprego: 'sim')[:resultado]).to eq('dentro')
      expect(calc('periodo_de_graca', **base, evento: evento, mais_de_120: 'sim', desemprego: 'nao')[:resultado]).to eq('fora')
      expect(calc('periodo_de_graca', **base, evento: evento, mais_de_120: 'sim')[:resultado]).to eq('depende')
    end

    it 'fora depois de 36 meses; facultativa só tem 6 meses' do
      expect(calc('periodo_de_graca', **base, evento: '2028-05-16', mais_de_120: 'sim', desemprego: 'sim')[:resultado]).to eq('fora')
      expect(calc('periodo_de_graca', **base, evento: '2025-11-15', facultativa: 'sim')[:resultado]).to eq('dentro')
      expect(calc('periodo_de_graca', **base, evento: '2025-11-16', facultativa: 'sim')[:resultado]).to eq('fora')
    end

    it 'depende quando falta data' do
      expect(calc('periodo_de_graca', evento: '2026-01-01')[:resultado]).to eq('depende')
    end
  end

  it 'renda_per_capita: até ¼ do salário mínimo (R$ 405,25 em 2026) é abaixo' do
    expect(calc('renda_per_capita', renda_total: '1621', moradores: '4')[:resultado]).to eq('abaixo')
    expect(calc('renda_per_capita', renda_total: '1621,04', moradores: '4')[:resultado]).to eq('acima')
    expect(calc('renda_per_capita', renda_total: '1621', moradores: '4')[:detalhe]).to include('405.25')
    expect(calc('renda_per_capita', renda_total: '1621', moradores: '0')[:resultado]).to eq('depende')
  end

  it 'prescricao_5_anos em três faixas' do
    expect(calc('prescricao_5_anos', data: '2023-01-01')[:resultado]).to eq('dentro')
    expect(calc('prescricao_5_anos', data: '2022-01-01')[:resultado]).to eq('ultimo_ano')
    expect(calc('prescricao_5_anos', data: '2021-10-13')[:resultado]).to eq('ultimo_ano')
    expect(calc('prescricao_5_anos', data: '2021-10-12')[:resultado]).to eq('prescrito')
  end

  it 'meses_ate_65' do
    expect(calc('meses_ate_65', nascimento: '1961-10-13')[:resultado]).to eq('ja_tem_65')
    res = calc('meses_ate_65', nascimento: '1962-04-20')
    expect(res[:resultado]).to eq('menos_de_65')
    expect(res[:detalhe]).to include('6 meses')
  end

  it 'data_prevista_parto: 40 semanas; pode pedir 28 dias antes' do
    res = calc('data_prevista_parto', semanas: '30')
    expect(res[:resultado]).to eq('aguardar')
    expect(res[:detalhe]).to include('22/12/2026').and include('24/11/2026')
    expect(calc('data_prevista_parto', semanas: '37')[:resultado]).to eq('ja_pode_pedir')
    expect(calc('data_prevista_parto', semanas: '50')[:resultado]).to eq('depende')
  end

  it 'prazo_inss: 45 dias da perícia ou 90 do requerimento' do
    expect(calc('prazo_inss', requerimento: '2026-09-01')[:resultado]).to eq('aguardar')
    expect(calc('prazo_inss', requerimento: '2026-07-01')[:resultado]).to eq('forcar_julgamento')
    expect(calc('prazo_inss', requerimento: '2026-08-01', pericia: '2026-08-25')[:resultado]).to eq('forcar_julgamento')
    expect(calc('prazo_inss')[:resultado]).to eq('depende')
  end

  it 'nome desconhecido = depende' do
    expect(calc('xablau')[:resultado]).to eq('depende')
  end

  describe 'leitura de valores' do
    it 'numero entende o jeito brasileiro' do
      expect(described_class.numero('R$ 1.200,50')).to eq(BigDecimal('1200.50'))
      expect(described_class.numero('R$ 1.200')).to eq(BigDecimal(1200))
      expect(described_class.numero('1200.5')).to eq(BigDecimal('1200.5'))
      expect(described_class.numero('abc')).to be_nil
      expect(described_class.numero('-')).to be_nil
    end

    it 'data aceita ISO e dd/mm/aaaa; data impossível = nil' do
      expect(described_class.data('12/03/2025')).to eq(Date.new(2025, 3, 12))
      expect(described_class.data('2025-03-12')).to eq(Date.new(2025, 3, 12))
      expect(described_class.data('31/02/2026')).to be_nil
      expect(described_class.data('ontem')).to be_nil
    end

    it 'sim_nao' do
      expect(described_class.sim_nao('Sim!')).to eq('sim')
      expect(described_class.sim_nao('não')).to eq('nao')
      expect(described_class.sim_nao('talvez')).to be_nil
    end
  end
end
