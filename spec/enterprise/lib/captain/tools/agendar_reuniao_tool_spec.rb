require 'rails_helper'

RSpec.describe Captain::Tools::AgendarReuniaoTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:lead) { create(:lead, account: account, name: 'Maria das Dores') }

  describe '#perform' do
    it 'guarda o horario proposto na sugestao, sem criar tarefa' do
      tool.perform(tool_context, lead_id: lead.id.to_s, quando: '2027-03-10 14:30', assunto: 'Fechamento')

      sugestao = account.copilot_suggestions.pending.last
      expect(sugestao.payload['acao']).to eq('reuniao')
      expect(sugestao.payload['titulo']).to eq('Fechamento')
      expect(Time.zone.parse(sugestao.payload['quando']).hour).to eq(14)
      expect(lead.lead_tasks.count).to eq(0)
    end

    it 'recusa data no passado' do
      expect(tool.perform(tool_context, lead_id: lead.id.to_s, quando: '2020-01-01 10:00')).to include('ja passou')
    end

    it 'recusa data que nao entende' do
      expect(tool.perform(tool_context, lead_id: lead.id.to_s, quando: 'semana que vem')).to include('Nao entendi a data')
    end
  end
end
