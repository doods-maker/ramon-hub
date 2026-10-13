require 'rails_helper'

RSpec.describe Captain::Tools::SimularHonorarioTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:thesis) do
    create(:thesis, account: account, name: 'Auxílio', honorario_percentual: 30, honorario_n_mensalidades: 3,
                    honorario_na_tabela: true)
  end

  describe '#perform' do
    it 'estima o honorario pela formula da tese e avisa que e estimativa' do
      lead = create(:lead, account: account, thesis: thesis)

      texto = tool.perform(tool_context, lead_id: lead.id.to_s, mensal: '2000', atrasados: '10000')

      expect(texto).to include('Honorario estimado (tese Auxílio): R$ 9000.00', '30% dos atrasados + 3 benefícios',
                               'R$ 10000.00', 'R$ 2000.00', 'estimativa')
    end

    it 'aceita numero com virgula' do
      lead = create(:lead, account: account, thesis: thesis)

      expect(tool.perform(tool_context, lead_id: lead.id.to_s, mensal: '2000,50', atrasados: '0')).to include('R$ 6001.50')
    end

    it 'tese fora da tabela: nao cita valor' do
      lead = create(:lead, account: account, thesis: create(:thesis, account: account, honorario_percentual: 30))

      texto = tool.perform(tool_context, lead_id: lead.id.to_s, mensal: 1, atrasados: 1)

      expect(texto).to include('Nao da para simular', 'fora da tabela')
    end

    it 'avisa quando a tese nao tem honorario configurado' do
      lead = create(:lead, account: account, thesis: create(:thesis, account: account, honorario_na_tabela: true))

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
