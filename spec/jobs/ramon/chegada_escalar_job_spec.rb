require 'rails_helper'

RSpec.describe Ramon::ChegadaEscalarJob do
  let(:account) { create(:account) }
  let(:chegada) do
    account.chegadas.create!(criado_por: create(:user, account: account), destinatario: create(:user, account: account),
                             cliente_nome: 'Maria')
  end

  it 'escala a chegada sem resposta' do
    described_class.perform_now(chegada.id)
    expect(chegada.reload.estado).to eq('escalado')
  end

  it 'não mexe na chegada já respondida' do
    chegada.update!(resposta: 'Já vou', respondido_em: Time.current)
    described_class.perform_now(chegada.id)
    expect(chegada.reload.escalado_em).to be_nil
  end

  it 'ignora chegada apagada' do
    expect { described_class.perform_now(0) }.not_to raise_error
  end
end
