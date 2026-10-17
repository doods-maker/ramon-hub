require 'rails_helper'

RSpec.describe Ramon::HorarioComercial do
  # 2026-10-05 = segunda; 2026-10-09 = sexta; 10 e 11 = fim de semana.
  def sp(texto)
    ActiveSupport::TimeZone['America/Sao_Paulo'].parse(texto)
  end

  def minutos(inicio, fim)
    described_class.minutos_entre(sp(inicio), sp(fim))
  end

  it 'dentro da janela conta o relógio' do
    expect(minutos('2026-10-05 09:00', '2026-10-05 09:07')).to eq(7)
  end

  it 'cruzando o almoço pula 12h00–13h30' do
    expect(minutos('2026-10-05 11:50', '2026-10-05 13:40')).to eq(20)
  end

  it 'começando às 12h10 só conta a partir de 13h30' do
    expect(minutos('2026-10-05 12:10', '2026-10-05 13:35')).to eq(5)
  end

  it 'sexta à noite até segunda conta só a segunda de manhã' do
    expect(minutos('2026-10-09 19:00', '2026-10-12 08:45')).to eq(15)
  end

  it 'fim de semana inteiro vale zero' do
    expect(minutos('2026-10-10 09:00', '2026-10-11 17:00')).to eq(0)
  end

  it 'aceita horário em UTC (converte pro fuso de SP)', :aggregate_failures do
    inicio = Time.utc(2026, 10, 5, 12, 0) # 09:00 em SP
    expect(described_class.minutos_entre(inicio, inicio + 10.minutes)).to eq(10)
    expect(described_class.minutos_entre(nil, inicio)).to eq(0)
  end

  it 'aberto? só em dia útil dentro da janela (fim exclusivo)', :aggregate_failures do
    expect(described_class.aberto?(sp('2026-10-06 10:00'))).to be(true) # terça
    expect(described_class.aberto?(sp('2026-10-06 12:30'))).to be(false)
    expect(described_class.aberto?(sp('2026-10-06 12:00'))).to be(false)
    expect(described_class.aberto?(sp('2026-10-10 10:00'))).to be(false) # sábado
  end

  describe 'com os limites da conta' do
    let(:account) { create(:account) }

    before do
      Ramon::IaLimites.gravar!(account, { 'horario' => { 'dias' => [1, 6], 'janelas' => [%w[10:00 11:00]] } }) # segunda e sábado, 10h–11h
    end

    it 'aberto? usa os dias e as faixas da conta; sem conta vale o padrão', :aggregate_failures do
      expect(described_class.aberto?(sp('2026-10-10 10:30'), account)).to be(true) # sábado
      expect(described_class.aberto?(sp('2026-10-06 10:30'), account)).to be(false) # terça fechada
      expect(described_class.aberto?(sp('2026-10-05 09:00'), account)).to be(false) # fora da faixa
      expect(described_class.aberto?(sp('2026-10-06 10:30'))).to be(true)
    end

    it 'minutos_entre e janelas seguem a conta', :aggregate_failures do
      expect(described_class.minutos_entre(sp('2026-10-05 09:00'), sp('2026-10-10 12:00'), account)).to eq(120)
      expect(described_class.janelas(account)).to eq([[[10, 0], [11, 0]]])
      expect(described_class.janelas).to eq(described_class::JANELAS)
    end
  end
end
