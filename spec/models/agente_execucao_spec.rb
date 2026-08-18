require 'rails_helper'

RSpec.describe AgenteExecucao do
  let(:account) { create(:account) }

  it 'grava com status válido' do
    expect(described_class.create!(account: account, pedido: 'resumo', status: 'ok', acoes: [{ 'tipo' => 'nota' }])).to be_persisted
  end

  it 'rejeita status desconhecido' do
    expect(described_class.new(account: account, pedido: 'x', status: 'zzz')).not_to be_valid
  end
end
