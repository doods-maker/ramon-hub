require 'rails_helper'

RSpec.describe Ramon::Fluxos::Horario do
  def sp(texto) = Time.find_zone!('America/Sao_Paulo').parse(texto)

  it 'seg–sex 8h–18h em SP' do
    expect(described_class.comercial?(sp('2026-10-05 08:00'))).to be(true)  # segunda
    expect(described_class.comercial?(sp('2026-10-05 18:00'))).to be(false)
    expect(described_class.comercial?(sp('2026-10-10 10:00'))).to be(false) # sábado
  end

  it 'próximo horário comercial' do
    expect(described_class.proximo(sp('2026-10-05 07:10'))).to eq(sp('2026-10-05 08:00'))
    expect(described_class.proximo(sp('2026-10-05 19:00'))).to eq(sp('2026-10-06 08:00'))
    expect(described_class.proximo(sp('2026-10-09 18:30'))).to eq(sp('2026-10-12 08:00')) # sexta → segunda
    expect(described_class.proximo(sp('2026-10-05 10:00'))).to eq(sp('2026-10-05 10:00'))
  end
end
