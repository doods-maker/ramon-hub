require 'rails_helper'

RSpec.describe Ramon::NightCopilotService do
  # A conta seeda o funil no after_create; 'Novo' tem stalled_after_days configurado.
  let(:account) { create(:account) }
  let(:stage_novo) { account.lead_stages.find_by(name: 'Novo') }

  def llm_result(content)
    Ramon::LlmClient::Result.new(content: content, input_tokens: 10, output_tokens: 5)
  end

  def stalled_lead(name: 'Maria da Silva')
    lead = create(:lead, account: account, lead_stage: stage_novo, name: name)
    lead.update_column(:stage_entered_at, 10.days.ago) # rubocop:disable Rails/SkipsModelValidations
    lead
  end

  it 'grava sugestão pendente de draft com o texto e o snapshot do lead' do
    lead = stalled_lead
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return(llm_result('{"tipo":"draft","texto":"Oi [nome], vamos retomar?","justificativa":"parado"}'))

    expect(described_class.new(account: account).perform).to eq(1)

    suggestion = lead.copilot_suggestions.pending.sole
    expect(suggestion.kind).to eq('draft')
    expect(suggestion.payload['texto']).to eq('Oi Maria, vamos retomar?')
    expect(suggestion.payload['lead_name']).to eq('Maria da Silva')
    expect(suggestion.run_at).to be_present
  end

  it 'aceita move_stage com etapa sugerida e justificativa' do
    lead = stalled_lead
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return(llm_result('{"tipo":"move_stage","etapa_sugerida":"Qualificado","justificativa":"triagem ok"}'))

    described_class.new(account: account).perform

    suggestion = lead.copilot_suggestions.sole
    expect(suggestion.kind).to eq('move_stage')
    expect(suggestion.payload['etapa_sugerida']).to eq('Qualificado')
  end

  it 'descarta tipo desconhecido e JSON inválido sem derrubar o lote' do
    stalled_lead(name: 'Maria da Silva')
    stalled_lead(name: 'João de Souza')
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return(llm_result('{"tipo":"enviar_agora","texto":"x"}'), llm_result('não é json'))

    expect(described_class.new(account: account).perform).to eq(0)
    expect(account.copilot_suggestions.count).to eq(0)
  end

  it 'falha do LLM pula o lead sem derrubar o lote' do
    stalled_lead(name: 'Maria da Silva')
    stalled_lead(name: 'João de Souza')
    allow(Ramon::LlmClient).to receive(:complete)
      .and_raise(Ramon::LlmClient::MissingApiKeyError, 'sem chave')

    expect(described_class.new(account: account).perform).to eq(0)
    expect(account.copilot_suggestions.count).to eq(0)
  end

  it 'pula lead que já tem sugestão pendente (idempotência)' do
    lead = stalled_lead
    create(:copilot_suggestion, account: account, lead: lead)
    expect(Ramon::LlmClient).not_to receive(:complete)

    expect(described_class.new(account: account).perform).to eq(0)
  end

  it 'sugestão aplicada/descartada não bloqueia rodada nova' do
    lead = stalled_lead
    create(:copilot_suggestion, account: account, lead: lead, status: 'applied')
    allow(Ramon::LlmClient).to receive(:complete)
      .and_return(llm_result('{"tipo":"alert","justificativa":"mencionou concorrente"}'))

    expect(described_class.new(account: account).perform).to eq(1)
    expect(lead.copilot_suggestions.pending.count).to eq(1)
  end

  it 'respeita o teto por conta via env' do
    with_modified_env(RAMON_NIGHT_COPILOT_LIMIT: '1') do
      stalled_lead(name: 'Maria da Silva')
      stalled_lead(name: 'João de Souza')
      allow(Ramon::LlmClient).to receive(:complete)
        .and_return(llm_result('{"tipo":"alert","justificativa":"risco"}'))

      expect(described_class.new(account: account).perform).to eq(1)
      expect(account.copilot_suggestions.count).to eq(1)
    end
  end

  it 'mascara o prompt e não envia o nome do lead ao LLM' do
    stalled_lead(name: 'Maria da Silva')
    captured = nil
    allow(Ramon::LlmClient).to receive(:complete) do |**kwargs|
      captured = kwargs[:user]
      llm_result('{"tipo":"alert","justificativa":"ok"}')
    end

    described_class.new(account: account).perform

    expect(captured).not_to include('Maria da Silva')
  end
end
