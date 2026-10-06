require 'rails_helper'

RSpec.describe Ramon::Telefone do
  it 'gera com/sem 55 e com/sem o 9º dígito' do
    expect(described_class.variantes('+55 (48) 99120-3381')).to contain_exactly('48991203381', '5548991203381', '4891203381', '554891203381')
  end

  it 'celular gravado sem o 9 também acha a grafia com 9' do
    expect(described_class.variantes('554891203381')).to include('48991203381')
  end

  it 'número curto ou vazio → nenhuma variante', :aggregate_failures do
    expect(described_class.variantes(nil)).to eq([])
    expect(described_class.variantes('3381')).to eq([])
  end

  it 'e164 devolve só as grafias com +55' do
    expect(described_class.e164('48 99120-3381')).to contain_exactly('+5548991203381', '+554891203381')
  end

  describe '.contato_por_variante' do
    let(:account) { create(:account) }
    let!(:contato) { create(:contact, account: account, phone_number: '+554891203381') }

    it 'acha o contato gravado sem o 9 pelo número com 9' do
      expect(described_class.contato_por_variante(account.contacts, '+5548991203381')).to eq(contato)
    end

    it 'número estrangeiro não procura variante' do
      expect(described_class.contato_por_variante(account.contacts, '+14155552671')).to be_nil
    end
  end
end
