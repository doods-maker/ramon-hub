require 'rails_helper'

RSpec.describe Ramon::StageSlug do
  describe '.label_for' do
    it 'prefixa fase- e gera slug minúsculo sem acento' do
      expect(described_class.label_for('Negociação')).to eq('fase-negociacao')
    end

    it 'troca espaços e símbolos por hífen único' do
      expect(described_class.label_for('Reunião  agendada!')).to eq('fase-reuniao-agendada')
    end

    it 'apara hifens das pontas' do
      expect(described_class.label_for('  Proposta enviada  ')).to eq('fase-proposta-enviada')
    end
  end
end
