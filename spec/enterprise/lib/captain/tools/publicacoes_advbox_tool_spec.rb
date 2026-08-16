require 'rails_helper'

RSpec.describe Captain::Tools::PublicacoesAdvboxTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }

  def envelope(itens)
    { 'offset' => 0, 'limit' => 5, 'totalCount' => itens.size, 'data' => itens, 'query' => {} }
  end

  describe '#perform' do
    it 'formats date, type and a truncated excerpt per publication' do
      allow(Ramon::AdvboxClient).to receive(:publications)
        .with(42, limit: 5)
        .and_return(envelope([{ 'start' => '2026-08-10', 'type' => 'Intimacao', 'publication' => "Texto   longo\n#{'x' * 500}" }]))

      resultado = tool.perform(tool_context, processo_id: 42)

      expect(resultado).to include('Publicacoes do processo 42 (1)')
      expect(resultado).to include('- 2026-08-10 [Intimacao]: Texto longo')
      expect(resultado.length).to be < 500
    end

    it 'caps the limit at 20 and accepts strings from the llm' do
      allow(Ramon::AdvboxClient).to receive(:publications).with(7, limit: 20).and_return(envelope([]))

      expect(tool.perform(tool_context, processo_id: '7', limite: '99')).to eq('Nenhuma publicacao encontrada para esse processo.')
    end

    it 'asks for a numeric id' do
      expect(tool.perform(tool_context, processo_id: 'abc')).to eq('Informe o processo_id (numero) do AdvBox.')
    end

    it 'returns a message when advbox refuses' do
      allow(Ramon::AdvboxClient).to receive(:publications).and_raise(Ramon::AdvboxClient::RequestError.new(404, 'nope'))

      expect(tool.perform(tool_context, processo_id: 1)).to eq('O AdvBox recusou a consulta (HTTP 404).')
    end

    it 'returns a message when advbox is down' do
      allow(Ramon::AdvboxClient).to receive(:publications).and_raise(Ramon::AdvboxClient::UnavailableError)

      expect(tool.perform(tool_context, processo_id: 1)).to eq('O AdvBox nao respondeu agora. Tente de novo em instantes.')
    end
  end
end
