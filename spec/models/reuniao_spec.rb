require 'rails_helper'

RSpec.describe Reuniao do
  let(:account) { create(:account) }
  let(:lead_stage) { create(:lead_stage, account: account) }
  let(:lead) { create(:lead, account: account, lead_stage: lead_stage) }

  it { is_expected.to belong_to(:account) }
  it { is_expected.to belong_to(:lead).optional }
  it { is_expected.to validate_inclusion_of(:status).in_array(described_class::STATUSES) }

  describe '#titulo_exibicao' do
    it 'uses titulo when present' do
      reuniao = build(:reuniao, titulo: 'Alinhamento')
      expect(reuniao.titulo_exibicao).to eq('Alinhamento')
    end

    it 'falls back to timestamp when blank' do
      reuniao = create(:reuniao, titulo: nil)
      expect(reuniao.titulo_exibicao).to include(reuniao.created_at.strftime('%d/%m'))
    end

    it 'usa a hora de Brasília no título automático' do
      reuniao = build(:reuniao, titulo: nil, created_at: Time.zone.parse('2026-10-05T13:30:00Z'))
      expect(reuniao.titulo_exibicao).to eq('Reunião de 05/10 10:30')
    end
  end

  it 'aceita reuniao sem lead (avulsa segue valendo)' do
    reuniao = described_class.create!(account: account, user: create(:user, account: account))
    expect(reuniao.lead).to be_nil
  end

  # destroy! real esbarra no FK de lead_activities (filhos do lead somem por
  # destroy_async, fora da transação da spec) — o nullify fica provado pela reflexão.
  it 'vincula lead e declara nullify na ponta do lead' do
    reuniao = described_class.create!(account: account, user: create(:user, account: account), lead: lead)
    expect(lead.reunioes.pluck(:id)).to eq([reuniao.id]) # ids: a classe pode vir recarregada conforme a ordem do shard
    expect(Lead.reflect_on_association(:reunioes).options[:dependent]).to eq(:nullify)
  end
end
