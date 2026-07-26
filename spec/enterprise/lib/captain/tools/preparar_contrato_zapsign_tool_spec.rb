require 'rails_helper'

RSpec.describe Captain::Tools::PrepararContratoZapsignTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:lead) { create(:lead, account: account, name: 'Maria das Dores') }

  describe '#perform' do
    it 'cria sugestao pendente sem chamar o zapsign' do
      expect(Ramon::ZapsignContractService).not_to receive(:new)

      resultado = tool.perform(tool_context, lead_id: lead.id.to_s, motivo: 'cliente aceitou')

      sugestao = account.copilot_suggestions.pending.last
      expect(sugestao.kind).to eq('acao')
      expect(sugestao.payload['acao']).to eq('zapsign')
      expect(resultado).to include('pendente de aprovacao')
    end

    it 'nao duplica sugestao pendente da mesma acao' do
      tool.perform(tool_context, lead_id: lead.id.to_s)

      expect { tool.perform(tool_context, lead_id: lead.id.to_s) }.not_to change(CopilotSuggestion, :count)
    end

    it 'avisa quando o contrato ja foi preparado' do
      lead.update!(custom_attributes: { 'zapsign' => { 'sign_url' => 'https://app.zapsign.com.br/abc' } })

      expect(tool.perform(tool_context, lead_id: lead.id.to_s)).to include('ja tem contrato preparado')
    end
  end
end
