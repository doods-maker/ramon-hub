require 'rails_helper'

RSpec.describe Captain::Copilot::SkillsService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:copiloto) { create(:captain_assistant, account: account) }
  let(:thread) { create(:captain_copilot_thread, account: account, user: user, assistant: copiloto) }
  let(:runner) { instance_double(Captain::Assistant::AgentRunnerService) }

  before do
    create(:captain_copilot_message, copilot_thread: thread, message_type: :user, message: { content: 'Situação do processo?' })
    allow(Captain::Assistant::AgentRunnerService).to receive(:new)
      .with(assistant: copiloto, source: 'copiloto_painel').and_return(runner)
  end

  def responder = described_class.new(copiloto, conversation_id: nil, copilot_thread_id: thread.id).responder

  it 'roda o agente com o contexto na pergunta e grava a resposta no painel', :aggregate_failures do
    allow(runner).to receive(:generate_response).and_return({ 'response' => 'Processo em perícia.' })

    expect(responder).to have_attributes(message_type: 'assistant', message: { 'content' => 'Processo em perícia.' })
    expect(runner).to have_received(:generate_response) do |message_history:|
      expect(message_history.last[:content]).to start_with('Contexto: hoje é')
    end
  end

  it 'erro do agente vira mensagem no painel (o "pensando" não fica girando)' do
    allow(runner).to receive(:generate_response).and_return({ 'response' => 'conversation_handoff', 'reasoning' => 'Error occurred: x' })

    expect(responder.message['content']).to eq(described_class::ERRO)
  end

  it '.usa? só para assistente da equipe (sem caixa) com skills ligadas e v2', :aggregate_failures do
    account.enable_features!('captain_integration_v2')
    create(:captain_scenario, assistant: copiloto, account: account, enabled: true)
    expect(described_class.usa?(copiloto.reload)).to be(true)

    create(:captain_inbox, captain_assistant: copiloto, inbox: create(:inbox, account: account))
    expect(described_class.usa?(copiloto.reload)).to be(false)
  end
end
