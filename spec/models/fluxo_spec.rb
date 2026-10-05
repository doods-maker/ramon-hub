require 'rails_helper'

RSpec.describe Fluxo do
  let(:account) { create(:account) }
  let(:grafo) { grafo_linear({ 'tipo' => 'manual' }, ['nota_privada', { 'texto' => 'oi' }]) }

  it 'publicar cria versões numeradas e fixa o gatilho' do
    fluxo = described_class.create!(account: account, nome: 'X', rascunho: grafo)
    expect(fluxo.publicar!(nil).numero).to eq(1)
    expect(fluxo.publicar!(nil).numero).to eq(2)
    expect(fluxo.reload.gatilho_tipo).to eq('manual')
    expect(fluxo.versao_publicada.numero).to eq(2)
  end

  it 'não publica desenho inválido' do
    fluxo = described_class.create!(account: account, nome: 'X', rascunho: { 'nos' => [], 'setas' => [] })
    expect { fluxo.publicar!(nil) }.to raise_error(Ramon::Fluxos::Grafo::Invalido)
    expect(fluxo.versoes.count).to eq(0)
  end

  it 'limite do dia conta só execuções reais de hoje (fuso SP)' do
    fluxo = fluxo_publicado(account, grafo, limite_dia: 1)
    lead = create(:lead, account: account)
    travel_to Time.zone.parse('2026-10-06 02:30:00 UTC') do # 05/10 23:30 em SP
      fluxo.execucoes.create!(account: account, versao: fluxo.versao_publicada, alvo: lead, status: 'concluida')
    end
    travel_to Time.zone.parse('2026-10-06 13:00:00 UTC') do
      expect(fluxo.limite_atingido?).to be(false)
      fluxo.execucoes.create!(account: account, alvo: lead, status: 'concluida', ensaio: true)
      expect(fluxo.limite_atingido?).to be(false)
      fluxo.execucoes.create!(account: account, versao: fluxo.versao_publicada, alvo: lead, status: 'concluida')
      expect(fluxo.limite_atingido?).to be(true)
    end
  end

  it 'fluxo do sistema nunca é executável' do
    fluxo_publicado(account, grafo, origem: 'sistema')
    expect(described_class.executaveis).to be_empty
  end
end
