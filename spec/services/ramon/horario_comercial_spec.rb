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
end
