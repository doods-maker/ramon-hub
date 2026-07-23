require 'rails_helper'

RSpec.describe Ramon::EsteiraBuilder do
  let(:account) { create(:account) }
  let(:active_stage) { account.lead_stages.find_by(is_won: false, is_lost: false) }

  def build
    described_class.new(account: account).perform
  end

  it 'lists overdue tasks with their reason, task_id and score' do
    lead = create(:lead, account: account, lead_stage: active_stage)
    task = create(:lead_task, account: account, lead: lead, title: 'Ligar', due_at: 2.days.ago)
    items = build[:items]
    expect(items.size).to eq(1)
    expect(items.first[:lead_id]).to eq(lead.id)
    expect(items.first[:task_id]).to eq(task.id)
    expect(items.first[:reasons].first).to eq({ key: 'TASK_OVERDUE', params: { title: 'Ligar' } })
    expect(items.first[:score]).to eq(80)
    expect(items.first[:suggested_action]).to eq('task')
  end

  it 'flags bleeding prescription as the most urgent reason' do
    create(:lead, account: account, lead_stage: active_stage,
                  dcb_em: 65.months.ago.to_date, benefit_monthly_value: 1350)
    item = build[:items].first
    expect(item[:score]).to eq(100)
    expect(item[:suggested_action]).to eq('contact')
    expect(item[:reasons].first[:key]).to eq('PRESCRIPTION_BLEEDING')
    expect(item[:reasons].first[:params]).to eq({ monthly: 1350.0 })
  end

  it 'flags upcoming prescription cliff without monthly value loss' do
    create(:lead, account: account, lead_stage: active_stage, dcb_em: 57.months.ago.to_date)
    item = build[:items].first
    expect(item[:reasons].first[:key]).to eq('PRESCRIPTION_SOON')
    expect(item[:reasons].first[:params][:months]).to be_between(1, 6)
    expect(item[:score]).to eq(85)
  end

  it 'merges multiple sources into one item with reasons sorted by urgency' do
    lead = create(:lead, account: account, lead_stage: account.lead_stages.find_by(name: 'Novo'),
                         dcb_em: 65.months.ago.to_date, benefit_monthly_value: 1350)
    lead.update_column(:stage_entered_at, 10.days.ago) # rubocop:disable Rails/SkipsModelValidations
    create(:lead_task, account: account, lead: lead, due_at: 1.day.ago)
    items = build[:items]
    expect(items.size).to eq(1)
    expect(items.first[:reasons].pluck(:key)).to eq(%w[PRESCRIPTION_BLEEDING TASK_OVERDUE STALLED])
    expect(items.first[:score]).to eq(100)
  end

  it 'lists fresh landing-page leads and awaiting_human triages' do
    lp_lead = create(:lead, account: account, lead_stage: active_stage, source: 'lp-auxilio-acidente')
    triaged = create(:lead, account: account, lead_stage: active_stage, name: 'Triado')
    triage = triaged.lead_triages.create!(account: account)
    triage.update_column(:status, 'awaiting_human') # rubocop:disable Rails/SkipsModelValidations
    items = build[:items]
    expect(items.pluck(:lead_id)).to eq([lp_lead.id, triaged.id])
    expect(items.first[:reasons].first[:key]).to eq('NEW_FROM_LP')
    expect(items.last[:reasons].first[:key]).to eq('AWAITING_HUMAN')
  end

  describe 'SLA de 1º contato' do
    let(:inbox) { create(:inbox, account: account, auto_create_lead: true, first_response_sla_minutes: 30) }

    def conversation_created_at(time)
      conversation = nil
      travel_to(time) { conversation = create(:conversation, account: account, inbox: inbox) }
      conversation
    end

    it 'flags leads past the first-response SLA with the SLA_BREACH reason' do
      conversation = conversation_created_at(2.hours.ago)
      lead = create(:lead, account: account, lead_stage: active_stage, conversation: conversation)
      item = build[:items].first
      expect(item[:lead_id]).to eq(lead.id)
      expect(item[:reasons].first).to eq({ key: 'SLA_BREACH', params: { minutes: 30 } })
      expect(item[:score]).to eq(82)
      expect(item[:suggested_action]).to eq('reply')
    end

    it 'skips replied and still-within-SLA conversations' do
      replied = conversation_created_at(2.hours.ago)
      replied.update!(first_reply_created_at: Time.current)
      fresh = create(:conversation, account: account, inbox: inbox)
      create(:lead, account: account, lead_stage: active_stage, conversation: replied)
      create(:lead, account: account, lead_stage: active_stage, conversation: fresh, name: 'Fresca')
      expect(build[:items]).to be_empty
    end
  end

  it 'orders by score then by value and sums the board' do
    cheap = create(:lead, account: account, lead_stage: active_stage, source: 'lp-x', value: 100)
    rich = create(:lead, account: account, lead_stage: active_stage, source: 'lp-y', value: 9000)
    bleeding = create(:lead, account: account, lead_stage: active_stage,
                             dcb_em: 65.months.ago.to_date, benefit_monthly_value: 500, value: 50)
    result = build
    expect(result[:items].pluck(:lead_id)).to eq([bleeding.id, rich.id, cheap.id])
    expect(result[:board][:total]).to eq(3)
    expect(result[:board][:value_sum]).to eq(9150.0)
  end

  it 'exposes thesis, persisted simulation and the last visible message' do
    thesis = create(:thesis, account: account)
    conversation = create(:conversation, account: account)
    lead = create(:lead, account: account, lead_stage: active_stage, source: 'lp-x',
                         thesis: thesis, conversation: conversation,
                         custom_attributes: { 'ultima_simulacao' => { 'atrasados' => '17000.00' } })
    # o lead precisa entrar na fila por algum coletor: task vencida
    create(:lead_task, account: account, lead: lead, due_at: 2.days.ago)
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'a' * 300)
    create(:message, account: account, conversation: conversation, message_type: :outgoing, private: true, content: 'nota interna')
    item = build[:items].first
    expect(item[:lead_id]).to eq(lead.id)
    expect(item[:thesis_id]).to eq(thesis.id)
    expect(item[:ultima_simulacao]).to eq({ 'atrasados' => '17000.00' })
    expect(item[:last_message]).to include(incoming: true, content: "#{'a' * 197}...")
    expect(item[:last_message][:at]).to be_a(Integer)
  end

  it 'returns nil last_message and ultima_simulacao when the lead has neither' do
    create(:lead, account: account, lead_stage: active_stage, source: 'lp-x')
    item = build[:items].first
    expect(item[:last_message]).to be_nil
    expect(item[:ultima_simulacao]).to be_nil
  end

  it 'drops leads already marked done today and counts them on the board' do
    done_lead = create(:lead, account: account, lead_stage: active_stage, source: 'lp-x')
    create(:lead, account: account, lead_stage: active_stage, source: 'lp-y', name: 'Fica')
    done_lead.lead_activities.create!(account: account, kind: described_class::DONE_KIND)
    result = build
    expect(result[:items].size).to eq(1)
    expect(result[:items].first[:name]).to eq('Fica')
    expect(result[:board][:done_today]).to eq(1)
  end
end
