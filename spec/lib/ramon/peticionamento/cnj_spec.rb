require 'rails_helper'

describe Ramon::Peticionamento::Cnj do
  # Monta um CNJ válido: DD = 98 - ((N + A + JTR + O + "00") % 97)
  def gerar_valido(seq, ano, jtr, origem)
    dd = format('%02d', 98 - (("#{seq}#{ano}#{jtr}#{origem}00").to_i % 97))
    "#{seq}-#{dd}.#{ano}.#{jtr[0]}.#{jtr[1, 2]}.#{origem}"
  end

  it 'normaliza' do
    expect(described_class.normalizar(' 5001234-56.2026.4.04.7207 ')).to eq('5001234-56.2026.4.04.7207')
    expect(described_class.normalizar('50012345620264047207')).to eq('5001234-56.2026.4.04.7207')
    expect(described_class.normalizar('123')).to be_nil
  end

  it 'valida o dígito (módulo 97)' do
    valido = gerar_valido('5001234', '2026', '404', '7207')
    expect(described_class.valido?(valido)).to be(true)
    expect(described_class.valido?(valido.delete('^0-9'))).to be(true)
    errado = valido.sub(/-(\d\d)\./) { "-#{format('%02d', (Regexp.last_match(1).to_i + 1) % 100)}." }
    expect(described_class.valido?(errado)).to be(false)
    expect(described_class.valido?('123')).to be(false)
  end

  it 'deduz o tribunal' do
    expect(described_class.tribunal('0000000-00.2026.4.04.7207')).to eq('trf4')
    expect(described_class.tribunal('0000000-00.2026.8.24.0075')).to eq('tjsc')
    expect(described_class.tribunal('0000000-00.2026.5.12.0041')).to eq('trt12')
    expect(described_class.tribunal('0000000-00.2026.8.26.0100')).to be_nil
  end
end
