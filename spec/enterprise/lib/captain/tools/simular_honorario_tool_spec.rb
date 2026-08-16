require 'rails_helper'

RSpec.describe Captain::Tools::SimularHonorarioTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:thesis) { create(:thesis, account: account, name: 'Auxílio', honorario_percentual: 30, honorario_n_mensalidades: 3) }

  describe '#perform' do
    it 'estima o honorario pela formula da tese e avisa que e estimativa' do
      lead = create(:lead, account: account, thesis: thesis)

      texto = tool.perform(tool_context, lead_id: lead.id.to_s, mensal: '1500', atrasados: '10000')

      expect(texto).to include('Honorario estimado (tese Auxílio): R$ 7500.00', '30.0% de R$ 10000.00', '3 x R$ 1500.00', 'estimativa')
    end

    it 'aceita numero com virgula' do
      lead = create(:lead, account: account, thesis: thesis)

      expect(tool.perform(tool_context, lead_id: lead.id.to_s, mensal: '1500,50', atrasados: '0')).to include('R$ 4501.50')
    end

    it 'avisa quando a tese nao tem honorario configurado' do
      lead = create(:lead, account: account, thesis: create(:thesis, account: account))

      expect(tool.perform(tool_context, lead_id: lead.id.to_s, mensal: 1, atrasados: 1)).to include('Nao da para simular')
    end

    it 'avisa quando o caso nao tem tese' do
      lead = create(:lead, account: account)

      expect(tool.perform(tool_context, lead_id: lead.id.to_s, mensal: 1, atrasados: 1)).to eq(described_class::SEM_TESE)
    end

    it 'pede o caso quando nao consegue resolver' do
      expect(tool.perform(tool_context, mensal: 1, atrasados: 1)).to eq(described_class::SEM_LEAD)
    end
  end
end
