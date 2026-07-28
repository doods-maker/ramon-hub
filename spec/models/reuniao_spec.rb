require 'rails_helper'

RSpec.describe Reuniao do
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
end
