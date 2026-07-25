require 'rails_helper'

RSpec.describe Captain::Tools::ConsultarDossieAdvboxTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }
  let(:dossie) do
    { processo: { 'id' => 42, 'process_number' => '5001234-56.2026.4.04.7200' },
      movimentacoes: [{ 'date' => '2026-07-01' }],
      publicacoes: [], tarefas: [], historico_tarefas: [] }
  end

  describe '#perform' do
    it 'devolve o dossie do processo em json' do
      allow(Ramon::AdvboxMcpService).to receive(:dossie).with(42).and_return(dossie)

      result = tool.perform(tool_context, processo_id: 42)

      expect(JSON.parse(result).dig('processo', 'id')).to eq(42)
    end

    it 'aceita o id como string vinda do llm' do
      allow(Ramon::AdvboxMcpService).to receive(:dossie).with(42).and_return(dossie)

      expect(tool.perform(tool_context, processo_id: '42')).to include('5001234')
    end

    it 'recusa id invalido sem chamar o advbox' do
      expect(Ramon::AdvboxMcpService).not_to receive(:dossie)

      expect(tool.perform(tool_context, processo_id: 'abc')).to eq('Informe o id numerico do processo no AdvBox.')
    end

    it 'trunca dossie muito grande' do
      gigante = { processo: { 'nota' => 'x' * (described_class::MAX_CHARS + 100) } }
      allow(Ramon::AdvboxMcpService).to receive(:dossie).with(42).and_return(gigante)

      result = tool.perform(tool_context, processo_id: 42)

      expect(result.length).to be <= described_class::MAX_CHARS + 40
      expect(result).to end_with('[dossie truncado]')
    end

    it 'devolve mensagem quando o advbox recusa' do
      allow(Ramon::AdvboxMcpService).to receive(:dossie)
        .and_raise(Ramon::AdvboxClient::RequestError.new(404, 'nao encontrado'))

      expect(tool.perform(tool_context, processo_id: 42)).to eq('O AdvBox recusou a consulta (HTTP 404).')
    end

    it 'devolve mensagem quando o advbox esta fora do ar' do
      allow(Ramon::AdvboxMcpService).to receive(:dossie)
        .and_raise(Ramon::AdvboxClient::UnavailableError)

      expect(tool.perform(tool_context, processo_id: 42)).to eq('O AdvBox nao respondeu agora. Tente de novo em instantes.')
    end
  end
end
