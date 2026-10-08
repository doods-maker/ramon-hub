require 'rails_helper'

RSpec.describe Ramon::Fluxos::Rotinas do
  let(:account) { create(:account) }
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' })) }
  # um "plano" de mentira: módulo com o contrato (ROTINAS, PENDENTE, rodar)
  let(:plano) do
    Module.new.tap do |m|
      m.const_set(:ROTINAS, { 'da_conta' => 'conta', 'do_lead' => 'lead' }.freeze)
      m.const_set(:PENDENTE, { 'da_conta' => ->(_account) { false } }.freeze)
      m.define_singleton_method(:rodar) do |nome, ctx|
        ctx.ensaio? ? "faria: #{nome}" : { resumo: "fez: #{nome}", vars: { 'x' => '1' } }
      end
    end
  end

  before { allow(described_class).to receive(:modulos).and_return([plano]) }

  # status concluida: fora do índice único (várias por exemplo)
  def ctx(alvo, ensaio: false)
    Ramon::Fluxos::Contexto.new(fluxo.execucoes.create!(account: account, alvo: alvo, ensaio: ensaio, status: 'concluida'))
  end

  it 'acha a rotina de qualquer plano: alvo, pendente e rodar (texto ou Hash)' do
    expect([described_class.alvo('da_conta'), described_class.alvo('dossie_passagem'), described_class.alvo('xyz')])
      .to eq(['conta', 'lead', nil])
    expect([described_class.pendente('da_conta', account), described_class.pendente('do_lead', account)]).to eq([false, nil])
    expect(described_class.rodar('da_conta', ctx(account))).to eq(saida: 's', resumo: 'fez: da_conta', vars: { 'x' => '1' })
    expect(described_class.rodar('da_conta', ctx(account, ensaio: true))).to eq(saida: 's', resumo: 'faria: da_conta')
  end

  it 'rotina da conta com um lead de alvo e nome desconhecido são passo impossível' do
    lead_ctx = ctx(create(:lead, account: account))
    expect { described_class.rodar('da_conta', lead_ctx) }.to raise_error(Ramon::Fluxos::PassoImpossivel, /conta toda/)
    expect { described_class.rodar('xyz', lead_ctx) }.to raise_error(Ramon::Fluxos::PassoImpossivel, 'rotina desconhecida: xyz')
  end

  it 'o passo rotina cai no registro para o que não é da B4.4' do
    expect(Ramon::Fluxos::Passos::Rotina.rotina({ 'rotina' => 'da_conta' }, ctx(account)))
      .to eq(saida: 's', resumo: 'fez: da_conta', vars: { 'x' => '1' })
  end

  it 'nome repetido entre planos (ou com as 5 da B4.4) não sobe' do
    outro = Module.new.tap { |m| m.const_set(:ROTINAS, { 'da_conta' => 'conta' }.freeze) }
    allow(described_class).to receive(:modulos).and_return([plano, outro])
    expect { described_class.alvo('do_lead') }.to raise_error(ArgumentError, 'rotina repetida: da_conta')
    b44 = Module.new.tap { |m| m.const_set(:ROTINAS, { 'pesquisa_nps' => 'lead' }.freeze) }
    allow(described_class).to receive(:modulos).and_return([b44])
    expect { described_class.alvo('x') }.to raise_error(ArgumentError, 'rotina repetida: pesquisa_nps')
  end

  it 'junta os grupos de migração dos planos; grupo repetido não sobe' do
    grupo = { env: 'RAMON_FLUXO_X', faz: 'x', fluxos: { 'x' => 'horario_conta' } }
    com_grupo = lambda do |nome|
      Module.new.tap do |m|
        m.const_set(:ROTINAS, {}.freeze)
        m.const_set(:GRUPOS, { nome => grupo }.freeze)
      end
    end
    allow(described_class).to receive(:modulos).and_return([plano, com_grupo.call('x')])
    expect(described_class.grupos).to eq('x' => grupo)
    allow(described_class).to receive(:modulos).and_return([com_grupo.call('x'), com_grupo.call('x')])
    expect { described_class.grupos }.to raise_error(ArgumentError, 'grupo de migração repetido: x')
  end
end
