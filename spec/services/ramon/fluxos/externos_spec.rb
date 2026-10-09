require 'rails_helper'

RSpec.describe Ramon::Fluxos::Externos do
  let(:account) { create(:account) }
  let(:recepcao) { create(:user, account: account) }
  let(:chegada) { account.chegadas.create!(criado_por: recepcao, destinatario: recepcao, cliente_nome: 'Maria') }
  let(:outra) { account.chegadas.create!(criado_por: recepcao, destinatario: recepcao, cliente_nome: 'Ana') }
  let(:codigo) { [] }
  let(:grupos) { Ramon::Fluxos::Migracao::GRUPOS.slice('chegada_cliente') }

  def evento(alvo = chegada) = described_class.evento('chegada_cliente', 'chegada_cliente', alvo) { codigo << alvo.id }

  def no_comando
    Ramon::Fluxos::Migracao.semear(account, 'chegada_cliente')
    Ramon::Fluxos::Migracao.mudar_modo!(account, 'chegada_cliente', 'normal')
  end

  def migrado = Ramon::Fluxos::Migracao.fluxo(account, 'chegada_cliente')

  it 'criar = o fluxo da chegada (o único de fora do funil no fluxo, 08/10), em sombra, ligado e publicado' do
    fluxos = grupos.keys.flat_map { |grupo| Ramon::Fluxos::Migracao.semear(account, grupo) }
    expect(fluxos.map { |f| [f.sistema_chave, f.gatilho_tipo] }).to eq(grupos.values.flat_map { |g| g[:fluxos].to_a })
    expect(fluxos.map { |f| [f.origem, f.modo, f.ativo, f.versao_publicada.present?] }.uniq).to eq([['usuario', 'sombra', true, true]])
    expect(Ramon::Fluxos::Migracao.descrever(account, 'chegada_cliente')).to include('o CÓDIGO faz a escalada da chegada de cliente')
    expect(Ramon::Fluxos::Disparo::DUAS_VEZES).to include(*described_class.gatilhos)
  end

  it 'código no comando (padrão): o código faz; o migrado só ensaia; o fluxo comum do gatilho ouve sem a decisão' do
    Ramon::Fluxos::Migracao.semear(account, 'chegada_cliente')
    comum = fluxo_publicado(account, grafo_linear({ 'tipo' => 'chegada_cliente' }))
    evento
    expect(codigo).to eq([chegada.id])
    expect(migrado.execucoes.pluck(:ensaio)).to eq([true])
    expect(comum.execucoes.map { |e| [e.ensaio, e.contexto['gatilho'].key?('assumido')] }).to eq([[false, false]])
  end

  it 'fluxo no comando: o código não faz; o migrado age' do
    with_modified_env(RAMON_FLUXO_CHEGADA: 'on') do
      no_comando
      evento
    end
    expect(codigo).to eq([])
    expect(migrado.execucoes.pluck(:ensaio, :status)).to eq([[false, 'esperando']])
  end

  it 'fluxo no comando mas ocupado com o mesmo alvo, ou o motor falhou: o código faz aquele evento — nunca nenhum, nunca dois' do
    with_modified_env(RAMON_FLUXO_CHEGADA: 'on') do
      no_comando
      migrado.execucoes.create!(account: account, alvo: chegada, status: 'esperando', retomar_em: 5.minutes.from_now)
      evento
      outra
      allow(Ramon::Fluxos::Disparo).to receive(:call).and_raise(StandardError, 'motor')
      evento(outra)
    end
    expect(codigo).to eq([chegada.id, outra.id])
    expect(migrado.execucoes.count).to eq(1) # só a viva; nenhum dos 2 eventos criou outra
  end
end
