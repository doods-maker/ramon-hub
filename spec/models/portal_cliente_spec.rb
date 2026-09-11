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

  it 'gera senha provisória de 6 dígitos que autentica; a anterior deixa de valer' do
    antiga = cliente.gerar_senha_provisoria!
    expect(antiga).to match(/\A\d{6}\z/)
    expect(cliente.authenticate_senha(antiga)).to be_truthy
    nova = cliente.gerar_senha_provisoria!
    expect(cliente.authenticate_senha(antiga)).to be false
    expect(cliente.authenticate_senha(nova)).to be_truthy
  end

  it 'senha escolhida precisa ter só números, mínimo 6' do
    expect(cliente.update(senha: '12345')).to be false
    expect(cliente.update(senha: 'abc123')).to be false
    expect(cliente.update(senha: '1234567')).to be true
  end

  it 'e-mail é opcional e CPF é obrigatório e único na conta' do
    c = create(:portal_cliente, email: '')
    expect(c.email).to be_nil
    expect(build(:portal_cliente, cpf: '')).not_to be_valid
    expect(build(:portal_cliente, account: c.account, cpf: c.cpf)).not_to be_valid
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
    expect(described_class.from_cpf('123.456.789-01')).to eq c
  end
end
