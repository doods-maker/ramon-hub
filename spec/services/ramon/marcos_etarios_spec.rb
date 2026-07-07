require 'rails_helper'

RSpec.describe Ramon::MarcosEtarios do
  let(:nascimento) { Date.new(1970, 3, 15) }

  it 'calcula os marcos de homem (65 urbana / 60 rural / 65 BPC)' do
    marcos = described_class.para(data_nascimento: nascimento, sexo: 'M')
    by_key = marcos.index_by { |m| m[:key] }
    expect(by_key['aposentadoria_idade_urbana'][:data]).to eq(Date.new(2035, 3, 15))
    expect(by_key['aposentadoria_idade_rural'][:data]).to eq(Date.new(2030, 3, 15))
    expect(by_key['bpc_loas_idoso'][:idade]).to eq(65)
  end

  it 'calcula os marcos de mulher (62 urbana / 55 rural)' do
    marcos = described_class.para(data_nascimento: nascimento, sexo: 'F')
    by_key = marcos.index_by { |m| m[:key] }
    expect(by_key['aposentadoria_idade_urbana'][:idade]).to eq(62)
    expect(by_key['aposentadoria_idade_rural'][:idade]).to eq(55)
  end

  it 'sem sexo: desdobra os marcos que variam e unifica os que não variam' do
    marcos = described_class.para(data_nascimento: nascimento, sexo: nil)
    urbanas = marcos.select { |m| m[:key] == 'aposentadoria_idade_urbana' }
    bpc = marcos.select { |m| m[:key] == 'bpc_loas_idoso' }
    expect(urbanas.map { |m| m[:idade] }).to contain_exactly(62, 65)
    expect(bpc.size).to eq(1)
    expect(bpc.first[:sexo]).to be_nil
  end

  it 'ordena por data e marca os já atingidos' do
    marcos = described_class.para(data_nascimento: Date.new(1950, 1, 1), sexo: 'M')
    expect(marcos.map { |m| m[:data] }).to eq(marcos.map { |m| m[:data] }.sort)
    expect(marcos).to all(include(atingido: true))
  end

  it 'retorna vazio sem data de nascimento' do
    expect(described_class.para(data_nascimento: nil)).to eq([])
  end
end
