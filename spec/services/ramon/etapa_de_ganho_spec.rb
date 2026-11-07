require 'rails_helper'

RSpec.describe Ramon::EtapaDeGanho do
  # A conta seeda o funil no after_create (Novo ... Fechado is_won / Perdido is_lost).
  let(:account) { create(:account) }
  let(:fechado) { account.lead_stages.find_by!(label: described_class::FECHADO) }

  it 'principal é Fechado mesmo com outras etapas de ganho antes dela', :aggregate_failures do
    docs = account.lead_stages.create!(name: 'Docs X', label: described_class::DOCUMENTOS, is_won: true, position: -5)

    expect(described_class.principal(account)).to eq(fechado)
    expect(described_class.entrada(build(:lead, account: account))).to eq(fechado)
    expect(docs.reload).to be_is_won
  end

  it 'sem Fechado, a primeira etapa de ganho por posição' do
    fechado.update!(label: nil)
    primeira = account.lead_stages.create!(name: 'Ganho 1', is_won: true, position: -9)

    expect(described_class.principal(account)).to eq(primeira)
  end

  it 'sem etapa de ganho, principal é nil e principal! levanta', :aggregate_failures do
    expect(described_class.principal!(account)).to eq(fechado)
    account.lead_stages.update_all(is_won: false) # rubocop:disable Rails/SkipsModelValidations

    expect(described_class.principal(account)).to be_nil
    expect { described_class.principal!(account) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
