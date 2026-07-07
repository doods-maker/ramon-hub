require 'rails_helper'

RSpec.describe Leads::TriageService do
  let(:account) { create(:account) }
  let(:agent) { account.triage_agents.first } # seedado pelo create(:account)
  let(:conversation) { create(:conversation, account: account) }
  let(:lead) { create(:lead, account: account, conversation: conversation) }
  let(:triage) { lead.lead_triages.create!(account: account, triage_agent: agent) }

  before do
    create(:message, account: account, conversation: conversation,
                     message_type: :incoming, content: 'Sofri um acidente em 2024')
    create(:message, account: account, conversation: conversation,
                     message_type: :outgoing, content: 'Pode me contar mais?')
    create(:message, account: account, conversation: conversation,
                     message_type: :incoming, content: 'nota interna', private: true)
  end

  def llm_result(content, input_tokens: 100, output_tokens: 30)
    Ramon::LlmClient::Result.new(content: content, input_tokens: input_tokens, output_tokens: output_tokens)
  end

  it 'monta o texto-fonte com as mensagens públicas e dados do lead' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result("análise...\nVIABILIDADE: alta"))
    described_class.new(triage).perform
    expect(triage.reload.source_text).to include('Sofri um acidente em 2024')
    expect(triage.source_text).to include('Pode me contar mais?')
    expect(triage.source_text).not_to include('nota interna')
  end

  it 'pseudonimiza nome, CPF e telefone antes de mandar pro LLM (LGPD)' do
    create(:message, account: account, conversation: conversation, message_type: :incoming,
                     content: 'Sou Maria das Dores, CPF 123.456.789-01, fone (48) 99999-8888')
    allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result('VIABILIDADE: alta'))
    described_class.new(triage).perform
    triage.reload
    expect(triage.source_text).to include('Lead: [nome]').and include('[cpf]').and include('[telefone]')
    expect(triage.source_text).not_to include('Maria')
    expect(triage.source_text).not_to include('123.456.789-01')
  end

  it 'extrai a viabilidade da linha VIABILIDADE e conclui done' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result("Resumo...\nVIABILIDADE: média"))
    described_class.new(triage).perform
    triage.reload
    expect(triage.status).to eq('done')
    expect(triage.viability).to eq('media')
    expect(triage.result).to include('Resumo')
    expect(triage.finished_at).to be_present
  end

  it 'accumulates token usage from the LLM response' do
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return(llm_result('análise VIABILIDADE: alta', input_tokens: 100, output_tokens: 30))
    described_class.new(triage).perform
    triage.reload
    expect(triage.input_tokens).to eq(100)
    expect(triage.output_tokens).to eq(30)
  end

  it 'passa o flag sensitive do agente pro LlmClient' do
    agent.update!(sensitive: true, provider: 'anthropic', model: 'claude-haiku-4-5-20251001')
    expect(Ramon::LlmClient).to receive(:complete)
      .with(hash_including(sensitive: true, provider: 'anthropic')).and_return(llm_result('VIABILIDADE: baixa'))
    described_class.new(triage).perform
  end

  it 'marca error com a mensagem quando o LLM falha' do
    allow(Ramon::LlmClient).to receive(:complete).and_raise(StandardError, 'boom')
    described_class.new(triage).perform
    triage.reload
    expect(triage.status).to eq('error')
    expect(triage.error_message).to include('boom')
  end

  it 'não propaga exceção quando o LLM falha e o próprio update! de erro também falha' do
    allow(Ramon::LlmClient).to receive(:complete).and_raise(StandardError, 'boom')
    allow(triage).to receive(:update!).with(status: 'running').and_call_original
    allow(triage).to receive(:update!).with(hash_including(status: 'error')).and_raise(StandardError, 'db down')
    expect(Rails.logger).to receive(:error).with(/falha ao gravar erro da triage/)
    expect { described_class.new(triage).perform }.not_to raise_error
  end

  it 'funciona sem conversa (só ficha do lead) e sem viabilidade detectável' do
    lead.update!(conversation: nil)
    allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result('resposta sem a linha esperada'))
    described_class.new(triage).perform
    triage.reload
    expect(triage.status).to eq('done')
    expect(triage.viability).to be_nil
  end

  it 'inclui a transcrição de mensagem só de áudio no texto-fonte' do
    audio_msg = create(:message, account: account, conversation: conversation,
                                 message_type: :incoming, content: nil)
    audio_msg.attachments.create!(account: account, file_type: :audio,
                                  meta: { transcribed_text: 'recebi a carta do INSS ontem' })
    allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result('VIABILIDADE: alta'))
    described_class.new(triage).perform
    expect(triage.reload.source_text).to include('recebi a carta do INSS ontem')
  end
end
