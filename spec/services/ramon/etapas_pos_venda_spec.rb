require 'rails_helper'

RSpec.describe Ramon::EtapasPosVenda do
  # A conta seeda o funil no after_create (Novo ... Fechado is_won / Perdido is_lost).
  let(:account) { create(:account) }

  def funil = account.lead_stages.reload.map { |s| [s.name, s.position, s.is_won] }

  it 'cria Documentos e Jurídico depois de Fechado, de ganho, com Perdido por último', :aggregate_failures do
    documentos, juridico = described_class.criar!(account)

    expect(account.lead_stages.reload.last(4).map(&:name)).to eq(%w[Fechado Documentos Jurídico Perdido])
    expect([documentos.label, juridico.label]).to eq(%w[fase-documentos fase-juridico])
    expect([documentos, juridico].map { |s| [s.is_won, s.probability] }).to eq([[true, 100], [true, 100]])
    expect(account.lead_stages.find_by!(label: 'fase-perdido')).to be_is_lost
  end

  it 'etapa já existente com o label vira ganho, sem mudar nome nem cor', :aggregate_failures do
    antiga = account.lead_stages.create!(name: 'Docs antiga', label: 'fase-documentos', color: '#123456', probability: 30)

    described_class.criar!(account)

    expect(antiga.reload).to have_attributes(is_won: true, probability: 100, name: 'Docs antiga', color: '#123456')
  end

  it 'rodar de novo não duplica nem mexe na ordem' do
    described_class.criar!(account)
    antes = funil

    described_class.criar!(account)

    expect(funil).to eq(antes)
  end
end
