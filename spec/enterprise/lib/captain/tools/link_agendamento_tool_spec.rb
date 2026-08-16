require 'rails_helper'

RSpec.describe Captain::Tools::LinkAgendamentoTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }

  describe '#perform' do
    it 'devolve o link e a frase sugerida quando configurado' do
      with_modified_env RAMON_CALCOM_URL: 'https://cal.com/ramon/30min' do
        expect(tool.perform(tool_context)).to include('https://cal.com/ramon/30min', 'Sugestao de frase')
      end
    end

    it 'avisa que nao esta configurado sem a env' do
      with_modified_env RAMON_CALCOM_URL: nil do
        expect(tool.perform(tool_context)).to eq(described_class::SEM_LINK)
      end
    end
  end
end
