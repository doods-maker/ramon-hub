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

  it 'janela própria do passo (B4.2): todos os dias, 7h–21h — como o SLA do código' do
    janela = { 'dias' => [0, 1, 2, 3, 4, 5, 6], 'inicio' => 7, 'fim' => 21 }
    expect(described_class.comercial?(sp('2026-10-10 07:00'), janela)).to be(true) # sábado
    expect(described_class.comercial?(sp('2026-10-10 20:59'), janela)).to be(true)
    expect(described_class.comercial?(sp('2026-10-10 21:00'), janela)).to be(false)
    expect(described_class.comercial?(sp('2026-10-11 06:59'), janela)).to be(false) # domingo cedo
    expect(described_class.proximo(sp('2026-10-10 22:00'), janela)).to eq(sp('2026-10-11 07:00'))
    expect(described_class.proximo(sp('2026-10-10 05:00'), { 'dias' => [1], 'inicio' => 9, 'fim' => 12 })).to eq(sp('2026-10-12 09:00'))
  end

  it 'janela válida: ao menos 1 dia de 0 a 6, início antes do fim, fim até 24; sem chaves = o padrão' do
    expect(described_class.janela_valida?({})).to be(true)
    expect(described_class.janela_valida?({ 'dias' => [0, 6], 'inicio' => 0, 'fim' => 24 })).to be(true)
    expect(described_class.janela_valida?({ 'dias' => [] })).to be(false)
    expect(described_class.janela_valida?({ 'inicio' => 18, 'fim' => 8 })).to be(false)
    expect(described_class.janela_valida?({ 'dias' => [7] })).to be(false)
    expect(described_class.janela_valida?({ 'fim' => 25 })).to be(false)
  end
end
