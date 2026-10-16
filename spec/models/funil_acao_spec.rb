require 'rails_helper'

RSpec.describe FunilAcao do
  let(:account) { create(:account) }
  let(:lead) { create(:lead, account: account) }

  def acao(attrs = {})
    described_class.create!({ account: account, lead: lead, peca: 'etapa_ia', acao: 'mover', ensaio: false }.merge(attrs))
  end

  it 'reais exclui ensaios; vivas exclui também as desfeitas' do
    viva = acao
    ensaio = acao(ensaio: true)
    desfeita = acao(desfeita_em: Time.current)

    expect(described_class.reais).to contain_exactly(viva, desfeita)
    expect(described_class.vivas).to contain_exactly(viva)
    expect(described_class.vivas).not_to include(ensaio)
  end

  it 'guarda desfazer como jsonb (padrão vazio)' do
    expect(acao.desfazer).to eq({})
    expect(acao(desfazer: { 'etapa' => 'fase-novo' }).reload.desfazer).to eq('etapa' => 'fase-novo')
  end
end
