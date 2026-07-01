require 'rails_helper'

RSpec.describe LeadStage do
  let(:account) { create(:account) }

  # Nota: a partir da Fase 2A Task 4, toda conta nova nasce auto-semeada com as
  # 8 etapas padrão (Novo..Perdido). Estes exemplos usam nomes/posições que não
  # colidem com a semente, para serem robustos com ou sem o seed.

  it 'valida nome único por conta' do
    account.lead_stages.create!(name: 'Etapa Custom 2A', position: 50)
    dup = account.lead_stages.build(name: 'Etapa Custom 2A', position: 51)
    expect(dup).not_to be_valid
  end

  it 'ordena por position (default_scope)' do
    primeira = account.lead_stages.create!(name: 'Etapa Topo 2A', position: -1)
    expect(account.lead_stages.first).to eq(primeira)
  end

  it 'expõe a coluna color' do
    expect(described_class.column_names).to include('color')
  end

  it 'mantém no máximo uma etapa de ganho' do
    a = account.lead_stages.create!(name: 'Ganho A', is_won: true)
    b = account.lead_stages.create!(name: 'Ganho B', is_won: true)
    expect(a.reload.is_won).to be(false)
    expect(b.reload.is_won).to be(true)
  end

  it 'mantém no máximo uma etapa de perda' do
    a = account.lead_stages.create!(name: 'Perda A', is_lost: true)
    b = account.lead_stages.create!(name: 'Perda B', is_lost: true)
    expect(a.reload.is_lost).to be(false)
    expect(b.reload.is_lost).to be(true)
  end
end
