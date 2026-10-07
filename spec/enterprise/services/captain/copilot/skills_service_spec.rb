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

  it 'guarda a skill dona da resposta e devolve o turno a ela (prévia → confirma? → sim)', :aggregate_failures do
    allow(runner).to receive(:generate_response).and_return({ 'response' => 'Prévia. Confirma?', 'agent_name' => 'Processos' })
    expect(responder.message).to eq('content' => 'Prévia. Confirma?', 'agent_name' => 'Processos')

    create(:captain_copilot_message, copilot_thread: thread, message_type: :user, message: { content: 'sim' })
    responder

    expect(runner).to have_received(:generate_response).with(
      message_history: [
        { role: 'user', content: 'Situação do processo?' },
        { role: 'assistant', content: 'Prévia. Confirma?', agent_name: 'Processos' },
        { role: 'user', content: a_string_starting_with('Contexto: hoje é').and(a_string_ending_with("\n\nsim")) }
      ]
    ).once
  end

  it 'resposta vazia do agente vira o aviso de erro' do
    allow(runner).to receive(:generate_response).and_return({ 'response' => '' })

    expect(responder.message['content']).to eq(described_class::ERRO)
  end

  it 'erro fora do runner também vira mensagem no painel e não sobe para o Sidekiq', :aggregate_failures do
    allow(Ramon::CopilotoPainel).to receive(:com_contexto).and_raise(StandardError, 'falhou')

    expect { responder }.not_to raise_error
    expect(thread.copilot_messages.reorder(:id).last.message['content']).to eq(described_class::ERRO)
  end

  it '.usa? só para assistente da equipe (sem caixa) com skills ligadas e v2', :aggregate_failures do
    account.enable_features!('captain_integration_v2')
    create(:captain_scenario, assistant: copiloto, account: account, enabled: true)
    expect(described_class.usa?(copiloto.reload)).to be(true)

    create(:captain_inbox, captain_assistant: copiloto, inbox: create(:inbox, account: account))
    expect(described_class.usa?(copiloto.reload)).to be(false)
  end
end
