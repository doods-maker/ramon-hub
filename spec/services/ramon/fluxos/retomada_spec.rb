require 'rails_helper'

RSpec.describe Ramon::Fluxos::Retomada do
  it 'migrado? = só o fluxo próprio da cadência; o desenho do sistema e os das outras migrações não' do
    expect(described_class.migrado?(Fluxo.new(origem: 'usuario', sistema_chave: 'cadencia'))).to be(true)
    expect(described_class.migrado?(Fluxo.new(origem: 'sistema', sistema_chave: 'cadencia'))).to be(false)
    expect(described_class.migrado?(Fluxo.new(origem: 'usuario', sistema_chave: 'sla_primeira_resposta'))).to be(false)
    expect(Ramon::Fluxos::Migracao.migrado?(Fluxo.new(origem: 'usuario', sistema_chave: 'cadencia'))).to be(true)
  end
end
