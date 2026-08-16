require 'rails_helper'

RSpec.describe Ramon::FollowUpDraftService do
  # A conta seeda o funil no after_create; 'Novo' tem stalled_after_days configurado.
  let(:account) { create(:account) }
  let(:stage_novo) { account.lead_stages.find_by(name: 'Novo') }

  def llm_result(content)
    Ramon::LlmClient::Result.new(content: content, input_tokens: 10, output_tokens: 5)
  end

  def stalled_lead(name: 'Maria da Silva')
    conversation = create(:conversation, account: account)
    lead = create(:lead, account: account, lead_stage: stage_novo, name: name, conversation_id: conversation.id)
    lead.update_column(:stage_entered_at, 10.days.ago) # rubocop:disable Rails/SkipsModelValidations
    lead
  end

  it 'cria nota RASCUNHO + tarefa follow_up e incrementa o contador do lead parado' do
    lead = stalled_lead
    allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result('Oi [nome], vamos retomar seu caso?'))

    expect(described_class.new(account: account).perform).to eq(1)

    note = lead.lead_notes.find_by("body LIKE 'RASCUNHO%'")
    expect(note.body).to start_with('RASCUNHO (revisar antes de enviar) — retomada nº 1:')
    expect(note.body).to include('Oi Maria, vamos retomar seu caso?')
    expect(lead.lead_tasks.find_by(kind: 'follow_up').title).to eq('Retomada nº 1')
    follow_up = lead.reload.custom_attributes['follow_up']
    expect(follow_up['tentativas']).to eq(1)
    expect(follow_up['ultima_em']).to be_present
  end

  it 'registra evento de automação na conversa (activity via job)' do
    lead = stalled_lead
    allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result('Oi [nome], vamos retomar seu caso?'))

    expect do
      described_class.new(account: account).perform
    end.to have_enqueued_job(Conversations::ActivityMessageJob).with(
      lead.conversation,
      hash_including(
        message_type: :activity,
        content_attributes: hash_including('ramon_event' => 'cadencia_follow_up')
      )
    )
  end

  it 'pula lead que já tem tarefa follow_up aberta' do
    lead = stalled_lead
    create(:lead_task, account: account, lead: lead, kind: 'follow_up', due_at: 1.day.from_now)
    expect(Ramon::LlmClient).not_to receive(:complete)

    expect(described_class.new(account: account).perform).to eq(0)
  end

  it 'pula lead com retomada há menos de 5 dias' do
    lead = stalled_lead
    lead.update!(custom_attributes: { 'follow_up' => { 'tentativas' => 1, 'ultima_em' => 2.days.ago.iso8601 } })

    expect(described_class.new(account: account).perform).to eq(0)
  end

  it 'retomada antiga (>5 dias) gera a tentativa seguinte' do
    lead = stalled_lead
    lead.update!(custom_attributes: { 'follow_up' => { 'tentativas' => 1, 'ultima_em' => 6.days.ago.iso8601 } })
    allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result('mensagem nova'))

    expect(described_class.new(account: account).perform).to eq(1)
    expect(lead.lead_notes.find_by("body LIKE 'RASCUNHO%'").body).to include('retomada nº 2')
    expect(lead.reload.custom_attributes.dig('follow_up', 'tentativas')).to eq(2)
  end

  it 'pula lead sem conversa vinculada' do
    lead = create(:lead, account: account, lead_stage: stage_novo)
    lead.update_column(:stage_entered_at, 10.days.ago) # rubocop:disable Rails/SkipsModelValidations

    expect(described_class.new(account: account).perform).to eq(0)
  end

  it 'respeita o teto diário por conta' do
    stub_const('Ramon::FollowUpDraftService::DAILY_CAP', 1)
    stalled_lead(name: 'Maria da Silva')
    stalled_lead(name: 'João de Souza')
    allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result('oi'))

    expect(described_class.new(account: account).perform).to eq(1)
    expect(account.lead_tasks.where(kind: 'follow_up').count).to eq(1)
  end

  it 'falha do LLM cai no texto de fallback sem derrubar o lote' do
    lead = stalled_lead
    allow(Ramon::LlmClient).to receive(:complete).and_raise(Ramon::LlmClient::MissingApiKeyError, 'sem chave')

    expect(described_class.new(account: account).perform).to eq(1)
    note = lead.lead_notes.find_by("body LIKE 'RASCUNHO%'")
    expect(note.body).to include('ainda tem interesse')
  end

  describe '#perform_for' do
    it 'gera rascunho pra 1 lead elegível (nota + task + evento) e retorna true' do
      lead = stalled_lead
      allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result('Oi [nome], vamos retomar seu caso?'))

      expect(described_class.new(account: account).perform_for(lead)).to be(true)
      expect(lead.lead_notes.last.body).to include('RASCUNHO')
      expect(lead.lead_tasks.open_tasks.where(kind: 'follow_up')).to exist
    end

    it 'lead inelegível (task follow_up aberta) → false e nada criado' do
      lead = stalled_lead
      lead.lead_tasks.create!(account: account, kind: 'follow_up', title: 'x', due_at: 1.day.from_now)

      expect { expect(described_class.new(account: account).perform_for(lead)).to be(false) }
        .not_to change(lead.lead_notes, :count)
    end
  end

  it 'manda 1 push resumo por conta ao final (não 1 por lead)' do
    with_modified_env(NTFY_TOPIC: 'ramon-teste') do
      stalled_lead(name: 'Maria da Silva')
      stalled_lead(name: 'João de Souza')
      allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result('oi'))

      expect { described_class.new(account: account).perform }
        .to have_enqueued_job(Ramon::NtfyPushJob).once
    end
  end
end
