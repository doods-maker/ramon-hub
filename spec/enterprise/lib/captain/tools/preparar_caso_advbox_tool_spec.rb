require 'rails_helper'

RSpec.describe Captain::Tools::PrepararCasoAdvboxTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:lead) { create(:lead, account: account, name: 'Maria das Dores') }

  describe '#perform' do
    it 'recusa caso que ainda nao foi ganho' do
      expect(tool.perform(tool_context, lead_id: lead.id.to_s)).to eq(described_class::SEM_GANHO)
      expect(account.copilot_suggestions.count).to eq(0)
    end

    it 'sugere quando o caso ja esta ganho' do
      lead.update!(lead_stage: create(:lead_stage, account: account, name: 'Ganho', is_won: true))

      tool.perform(tool_context, lead_id: lead.id.to_s)

      expect(account.copilot_suggestions.pending.last.payload['acao']).to eq('advbox')
    end

    it 'avisa quando o caso ja foi sincronizado' do
      lead.update!(lead_stage: create(:lead_stage, account: account, name: 'Ganho', is_won: true),
                   custom_attributes: { 'advbox' => { 'sincronizado_em' => '2026-07-20T10:00:00Z' } })

      expect(tool.perform(tool_context, lead_id: lead.id.to_s)).to include('ja foi sincronizado')
    end
  end
end
