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

  describe '.unique_label_for' do
    let(:account) { create(:account) }

    it 'devolve o label base quando está livre' do
      expect(described_class.unique_label_for(account, 'Proposta enviada')).to eq('fase-proposta-enviada')
    end

    it 'acrescenta sufixo quando outra etapa (renomeada) ainda usa o label' do
      account.lead_stages.create!(name: 'Proposta renomeada', label: 'fase-proposta', position: 90)
      expect(described_class.unique_label_for(account, 'Proposta')).to eq('fase-proposta-2')
    end
  end
end
