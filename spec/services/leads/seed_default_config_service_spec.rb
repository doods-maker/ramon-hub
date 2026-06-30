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

  it 'NÃO cria Labels fase-* no seed (criadas sob demanda no StageLabelSync)' do
    account = create(:account)
    expect(account.labels.where('title LIKE ?', 'fase-%')).to be_empty
  end

  it 'é idempotente (re-rodar não duplica etapas)' do
    account = create(:account)
    expect { described_class.new(account).perform }.not_to(change { account.lead_stages.count })
  end
end
