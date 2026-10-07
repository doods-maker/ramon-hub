require 'rails_helper'

RSpec.describe Ramon::Fluxos::Migracao do
  let(:account) { create(:account) }

  it 'migração desconhecida é recusada com a lista das que existem' do
    expect { described_class.assumiu?(account, 'xyz') }.to raise_error(ArgumentError, /desconhecida: xyz.*reunioes/)
  end

  it 'migrado? = fluxo próprio (origem usuario) com a chave de uma migração; o desenho do sistema e os demais não' do
    expect(described_class.migrado?(Fluxo.new(origem: 'usuario', sistema_chave: 'lembretes_reuniao'))).to be(true)
    expect(described_class.migrado?(Fluxo.new(origem: 'sistema', sistema_chave: 'lembretes_reuniao'))).to be(false)
    expect(described_class.migrado?(Fluxo.new(origem: 'usuario', sistema_chave: nil))).to be(false)
  end

  it 'a API genérica e a das reuniões são a mesma coisa' do
    expect(described_class.gatilhos('reunioes')).to eq(Ramon::Fluxos::Reunioes::GATILHOS)
    expect(described_class.descrever(account, 'reunioes')).to eq('Agora o CÓDIGO faz o agendamento (os fluxos ensaiam).')
  end

  it 'grupo com limite_devolve: false segue no comando mesmo com limite do dia (o código também tem teto)' do
    teste = { env: 'RAMON_FLUXO_TESTE', faz: 'o teste', fluxos: { 'teste_limite' => 'lead_criado' }.freeze, limite_devolve: false }
    stub_const("#{described_class}::GRUPOS", described_class::GRUPOS.merge('teste' => teste))
    grafo = grafo_linear({ 'tipo' => 'lead_criado' }, ['parar', {}])
    fluxo_publicado(account, grafo, sistema_chave: 'teste_limite', modo: 'normal', limite_dia: 15)
    with_modified_env(RAMON_FLUXO_TESTE: 'on') { expect(described_class.assumiu?(account, 'teste')).to be(true) }
  end

  it 'SLA (B4.2): criar = 1 fluxo em sombra, ligado e publicado; virar exige RAMON_FLUXO_SLA; cada migração tem a sua chave' do
    fluxos = described_class.semear(account, 'sla')
    expect(fluxos.map { |f| [f.sistema_chave, f.gatilho_tipo, f.modo, f.ativo, f.versao_publicada_id.present?] })
      .to eq([['sla_primeira_resposta', 'conversa_criada', 'sombra', true, true]])
    expect { described_class.mudar_modo!(account, 'sla', 'normal') }.to raise_error(ArgumentError, /RAMON_FLUXO_SLA/)
    with_modified_env(RAMON_FLUXO_SLA: 'on') do
      expect(described_class.assumiu?(account, 'sla')).to be(false) # ainda em sombra
      described_class.mudar_modo!(account, 'sla', 'normal')
      expect(described_class.assumiu?(account, 'sla')).to be(true)
      expect(described_class.assumiu?(account, 'reunioes')).to be(false)
    end
    expect(described_class.descrever(account, 'sla')).to include('Agora o CÓDIGO faz o aviso de SLA da 1ª resposta')
  end
end
