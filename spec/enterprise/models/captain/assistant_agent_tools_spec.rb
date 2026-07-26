require 'rails_helper'

# ramon: sem FAQ cadastrada o agente nao deve receber a faq_lookup — nesta
# instalacao ela depende de embeddings da OpenAI e sempre falha, queimando o
# turno do agente.
RSpec.describe Captain::Assistant do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }

  describe '#agent_tools' do
    it 'gives the agent only the handoff tool when there is no faq' do
      expect(assistant.send(:agent_tools).map { |tool| tool.class.name })
        .to eq(['Captain::Tools::HandoffTool'])
    end

    it 'adds the faq lookup once there is a faq to search' do
      create(:captain_assistant_response, assistant: assistant, account: account)

      expect(assistant.send(:agent_tools).map { |tool| tool.class.name })
        .to contain_exactly('Captain::Tools::FaqLookupTool', 'Captain::Tools::HandoffTool')
    end
  end
end
