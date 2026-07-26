require 'rails_helper'

RSpec.describe Captain::Tools::MoverEtapaTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:stage) { create(:lead_stage, account: account, name: 'Qualificado', position: 1) }
  let(:lead) { create(:lead, account: account, lead_stage: stage, name: 'Maria das Dores') }

  describe '#perform' do
    it 'sugere a etapa aberta pelo nome, sem mover o caso' do
      create(:lead_stage, account: account, name: 'Em reunião', position: 2)

      tool.perform(tool_context, lead_id: lead.id.to_s, etapa: 'em reunião')

      expect(account.copilot_suggestions.pending.last.payload['etapa_sugerida']).to eq('Em reunião')
      expect(lead.reload.lead_stage_id).to eq(stage.id)
    end

    it 'recusa etapa de ganho e lista as abertas' do
      create(:lead_stage, account: account, name: 'Ganho', is_won: true, position: 3)

      resultado = tool.perform(tool_context, lead_id: lead.id.to_s, etapa: 'Ganho')

      expect(resultado).to include('Etapa nao encontrada').and include('Qualificado')
      expect(account.copilot_suggestions.count).to eq(0)
    end

    it 'avisa quando o caso ja esta na etapa pedida' do
      expect(tool.perform(tool_context, lead_id: lead.id.to_s, etapa: 'Qualificado')).to include('ja esta na etapa')
    end
  end
end
