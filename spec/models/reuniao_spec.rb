require 'rails_helper'

RSpec.describe Reuniao do
  let(:account) { create(:account) }
  let(:lead_stage) { create(:lead_stage, account: account) }
  let(:lead) { create(:lead, account: account, lead_stage: lead_stage) }

  it { is_expected.to belong_to(:account) }
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
  end

  it 'aceita reuniao sem lead (avulsa segue valendo)' do
    reuniao = described_class.create!(account: account, user: create(:user, account: account))
    expect(reuniao.lead).to be_nil
  end

  it 'vincula lead e sobrevive ao delete do lead (nullify)' do
    reuniao = described_class.create!(account: account, user: create(:user, account: account), lead: lead)
    expect(lead.reunioes).to eq([reuniao])
    lead.destroy!
    expect(reuniao.reload.lead_id).to be_nil
  end
end
