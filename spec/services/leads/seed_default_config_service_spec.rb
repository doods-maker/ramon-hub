require 'rails_helper'

RSpec.describe Leads::SeedDefaultConfigService do
  let(:account) { create(:account) }

  it 'semeia 8 etapas, 7 benefícios e 3 prioridades, idempotente' do
    described_class.new(account).perform
    described_class.new(account).perform # idempotência

    expect(account.lead_stages.count).to eq(8)
    expect(account.benefit_types.count).to eq(7)
    expect(account.lead_priorities.count).to eq(3)
    expect(account.lead_stages.find_by(name: 'Fechado')).to be_is_won
    expect(account.lead_stages.find_by(name: 'Perdido')).to be_is_lost
  end

  it 'grava a label canônica em cada etapa semeada' do
    account = create(:account)
    expect(account.lead_stages.find_by(name: 'Novo').label).to eq('fase-novo')
    expect(account.lead_stages.find_by(name: 'Qualificação').label).to eq('fase-qualificacao')
    expect(account.lead_stages.find_by(name: 'Última chance').label).to eq('fase-ultima-chance')
  end

  it 'cria as Labels nativas fase-* (uma por etapa)' do
    account = create(:account)
    titles = account.labels.pluck(:title)
    expect(titles).to include('fase-novo', 'fase-qualificacao', 'fase-fechado', 'fase-perdido')
    expect(account.labels.find_by(title: 'fase-novo').show_on_sidebar).to be(true)
  end

  it 'é idempotente (re-rodar não duplica labels nem etapas)' do
    account = create(:account)
    expect { described_class.new(account).perform }
      .to not_change { account.lead_stages.count }.and not_change { account.labels.count }
  end
end
