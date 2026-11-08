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

    # Teste ponta a ponta de 07/11: com o passo a passo só no sub-agente da skill, o assistente de Documentos passava para a
    # equipe direto. O assistente de etapa leva as tools das próprias skills.
    context 'when the assistant runs a funnel stage' do
      before do
        create(:captain_scenario, assistant: assistant, account: account,
                                  instruction: 'Mande [Imagem do passo a passo](tool://enviar_passo_a_passo) com o tema.')
      end

      it 'keeps only the handoff while no stage points to it' do
        expect(assistant.send(:agent_tools).map { |tool| tool.class.name }).to eq(['Captain::Tools::HandoffTool'])
      end

      it 'carries the tools of its enabled skills, minus the ones the Perfil da IA blocks', :aggregate_failures do
        create(:lead_stage, account: account, captain_assistant_id: assistant.id)

        expect(assistant.send(:agent_tools).map { |tool| tool.class.name })
          .to eq(['Captain::Tools::HandoffTool', 'Captain::Tools::EnviarPassoAPassoTool'])
        expect(assistant.send(:agent_tools, ['enviar_passo_a_passo']).map { |tool| tool.class.name })
          .to eq(['Captain::Tools::HandoffTool'])
      end
    end
  end
end
