require 'rails_helper'

RSpec.describe Ramon::Pseudonymizer do
  it 'mascara o nome completo e as partes soltas, ignorando conectivos' do
    out = described_class.mask('Maria das Dores relatou; a Maria mandou o CNIS.', names: ['Maria das Dores'])
    expect(out).to eq('[nome] relatou; a [nome] mandou o CNIS.')
  end

  it 'mascara CPF formatado e corrido' do
    out = described_class.mask('CPF 123.456.789-01 ou 12345678901')
    expect(out).to eq('CPF [cpf] ou [cpf]')
  end

  it 'mascara RG rotulado e no formato pontuado' do
    out = described_class.mask('Meu RG é 4567890, da esposa é 12.345.678-9 e o RG: 1.234.567 também.')
    expect(out).to eq('Meu [rg], da esposa é [rg] e o [rg] também.')
  end

  it 'não confunde RG com valores em reais na casa do milhão' do
    text = 'O acordo foi de R$ 1.234.567,89 no total.'
    expect(described_class.mask(text)).to eq(text)
  end

  it 'mascara telefones nos formatos BR comuns' do
    out = described_class.mask('Fones: (48) 99999-8888, +55 48 3622-1234 e 999998888')
    expect(out).to eq('Fones: [telefone], [telefone] e [telefone]')
  end

  it 'mascara e-mail, CEP e endereço' do
    out = described_class.mask('Mora na Rua das Flores, 123. CEP 88700-000, e-mail maria@exemplo.com')
    expect(out).to eq('Mora na [endereco]. CEP [cep], e-mail [email]')
  end

  it 'preserva valores em reais, datas e números de benefício curtos' do
    text = 'Recebia R$ 1.500,00, se acidentou em 12/03/2024 e tem B91 desde 2019.'
    expect(described_class.mask(text)).to eq(text)
  end

  it 'não mascara "rua" em narrativa sem número de endereço' do
    text = 'Caí na rua e machuquei o ombro voltando da obra.'
    expect(described_class.mask(text)).to eq(text)
  end

  it 'tolera lista de nomes com nil e texto nil' do
    expect(described_class.mask(nil, names: [nil, ''])).to eq('')
  end
end
