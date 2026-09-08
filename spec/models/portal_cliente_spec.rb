require 'rails_helper'

RSpec.describe PortalCliente do
  let(:cliente) { create(:portal_cliente) }

  it 'gera código de 6 dígitos que valida uma vez e expira em 10 minutos' do
    codigo = cliente.gerar_codigo!
    expect(codigo).to match(/\A\d{6}\z/)
    expect(cliente.codigo_valido?(codigo)).to be true
    expect(cliente.codigo_valido?('000000')).to be false

    travel_to(11.minutes.from_now) { expect(cliente.codigo_valido?(codigo)).to be false }
  end

  it 'consome o código ao validar' do
    codigo = cliente.gerar_codigo!
    cliente.consumir_codigo!
    expect(cliente.codigo_valido?(codigo)).to be false
  end

  it 'só permite atualizar a cada 6 horas' do
    expect(cliente.pode_atualizar?).to be true
    cliente.update!(atualizacao_pedida_em: 1.hour.ago)
    expect(cliente.pode_atualizar?).to be false
    cliente.update!(atualizacao_pedida_em: 7.hours.ago)
    expect(cliente.pode_atualizar?).to be true
  end

  it 'acha o processo do espelho pelo id' do
    cliente.update!(processos: [{ 'id' => 42, 'numero' => '500' }])
    expect(cliente.processo(42)['numero']).to eq '500'
    expect(cliente.processo(1)).to be_nil
  end

  it 'normaliza e-mail e CPF' do
    c = create(:portal_cliente, email: ' Maria@Exemplo.COM ', cpf: '123.456.789-01')
    expect(c.email).to eq 'maria@exemplo.com'
    expect(c.cpf).to eq '12345678901'
  end
end
