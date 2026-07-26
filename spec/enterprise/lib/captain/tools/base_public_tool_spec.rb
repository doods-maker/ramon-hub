require 'rails_helper'

# O wrapper de #execute e o que alimenta a tela Execucoes — o instrumentation
# nativo do Captain so grava com OpenTelemetry ligado.
RSpec.describe Captain::Tools::BasePublicTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:lead) { create(:lead, account: account, dcb_em: 1.year.ago.to_date) }

  describe '#execute' do
    it 'registra a execucao com tool, parametros e resultado' do
      tool = Captain::Tools::ChecarPrescricaoTool.new(assistant)

      resultado = tool.execute(tool_context, lead_id: lead.id.to_s)

      run = Captain::ToolRun.last
      expect(run).to have_attributes(tool_name: 'checar_prescricao', status: 'ok', account_id: account.id,
                                     assistant_id: assistant.id, lead_id: lead.id)
      expect(run.resultado).to eq(resultado)
      expect(run.duration_ms).to be >= 0
    end

    it 'registra o erro e devolve mensagem ao llm em vez de derrubar a resposta' do
      tool = Captain::Tools::ChecarPrescricaoTool.new(assistant)
      allow(tool).to receive(:perform).and_raise(StandardError, 'boom')

      expect(tool.execute(tool_context, lead_id: lead.id.to_s)).to eq(described_class::ERRO_NA_TOOL)
      expect(Captain::ToolRun.last).to have_attributes(status: 'erro')
      expect(Captain::ToolRun.last.resultado).to include('boom')
    end

    it 'nao derruba a tool quando o registro falha' do
      tool = Captain::Tools::ChecarPrescricaoTool.new(assistant)
      allow(Captain::ToolRun).to receive(:create!).and_raise(ActiveRecord::StatementInvalid)

      expect { tool.execute(tool_context, lead_id: lead.id.to_s) }.not_to raise_error
    end
  end
end
