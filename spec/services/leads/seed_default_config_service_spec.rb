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

  it 'grava a cor de cada etapa a partir de STAGES' do
    described_class.new(account).perform
    novo = account.lead_stages.find_by(name: 'Novo')
    fechado = account.lead_stages.find_by(name: 'Fechado')
    expect(novo.color).to eq('#6b7280')
    expect(fechado.color).to eq('#22c55e')
  end

  it 'faz backfill da cor ao re-rodar quando a etapa está sem cor' do
    described_class.new(account).perform
    novo = account.lead_stages.find_by(name: 'Novo')
    novo.update!(color: nil)
    described_class.new(account).perform
    expect(novo.reload.color).to eq('#6b7280')
  end

  it 'semeia as 5 teses de incapacidade com mais de 60 itens de playbook' do
    expect(account.theses.count).to eq(5)
    expect(ThesisItem.where(thesis: account.theses).count).to be > 60
  end

  it 'semeia a tese de auxílio-acidente com suas seções' do
    tese = account.theses.find_by(name: 'Auxílio-acidente (B36)')
    expect(tese.thesis_items.pluck(:section).uniq).to match_array(ThesisItem::SECTIONS)
  end

  it 'é idempotente ao rodar o seed de teses 2x (não duplica teses)' do
    expect { described_class.new(account).perform }.not_to(change { account.theses.count })
  end

  it 'é idempotente ao rodar o seed de teses 2x (não duplica itens)' do
    expect { described_class.new(account).perform }.not_to(change { ThesisItem.where(thesis: account.theses).count })
  end

  it 'semeia 1 agente de triagem deepseek e é idempotente' do
    expect(account.triage_agents.count).to eq(1)
    expect(account.triage_agents.first.provider).to eq('deepseek')
    expect { described_class.new(account).perform }.not_to(change { account.triage_agents.count })
  end
end
