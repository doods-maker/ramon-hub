require 'rails_helper'

RSpec.describe Ramon::Telefone do
  it 'gera com/sem 55 e com/sem o 9º dígito' do
    expect(described_class.variantes('+55 (48) 99120-3381')).to contain_exactly('48991203381', '5548991203381', '4891203381', '554891203381')
  end

  it 'celular gravado sem o 9 também acha a grafia com 9' do
    expect(described_class.variantes('554891203381')).to include('48991203381')
  end

  it 'número curto ou vazio → nenhuma variante' do
    expect(described_class.variantes(nil)).to eq([])
    expect(described_class.variantes('3381')).to eq([])
  end
end
