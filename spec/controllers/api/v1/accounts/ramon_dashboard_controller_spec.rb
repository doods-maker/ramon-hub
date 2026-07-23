require 'rails_helper'

RSpec.describe 'Ramon Dashboard API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_dashboard" }
  let(:active_stage) { account.lead_stages.find_by(is_won: false, is_lost: false) }

  it 'lists overdue tasks under today with lead name' do
    lead = create(:lead, account: account, lead_stage: active_stage)
    create(:lead_task, account: account, lead: lead, title: 'Atrasada', due_at: 2.days.ago)
    get url, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    block = response.parsed_body['today']['tasks_overdue']
    expect(block['count']).to eq(1)
    expect(block['items'].first['title']).to eq('Atrasada')
    expect(block['items'].first['lead_name']).to eq(lead.name)
  end

  it 'lists stalled active leads with days_in_stage' do
    lead = create(:lead, account: account, lead_stage: account.lead_stages.find_by(name: 'Novo'))
    lead.update_column(:stage_entered_at, 10.days.ago) # rubocop:disable Rails/SkipsModelValidations
    get url, headers: agent.create_new_auth_token, as: :json
    block = response.parsed_body['today']['stalled']
    expect(block['count']).to eq(1)
    expect(block['items'].first['id']).to eq(lead.id)
    expect(block['items'].first['days_in_stage']).to be >= 9
  end

  it 'counts weekly wins and sums funnel value' do
    won_stage = account.lead_stages.find_by(is_won: true)
    create(:lead, account: account, lead_stage: won_stage, value: 1500)
    get url, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['week']['won']).to eq(1)
    row = response.parsed_body['funnel'].find { |r| r['stage_id'] == won_stage.id }
    expect(row['count']).to eq(1)
    expect(row['total_value']).to eq(1500.0)
    expect(row['total_value']).to be_a(Float)
    empty_row = response.parsed_body['funnel'].find { |r| r['stage_id'] == active_stage.id }
    expect(empty_row['total_value']).to eq(0.0)
    expect(empty_row['weighted_value']).to be_a(Float)
  end

  it 'caso de cálculo fica fora do funil, da semana e do radar' do
    create(:lead, account: account, lead_stage: active_stage, value: 999, source: Lead::FONTE_CALCULO)
    get url, headers: agent.create_new_auth_token, as: :json
    row = response.parsed_body['funnel'].find { |r| r['stage_id'] == active_stage.id }
    expect(row['count']).to eq(0)
    expect(response.parsed_body['week']['created']).to eq(0)
  end

  it 'lists fresh landing-page leads without follow-up' do
    create(:lead, account: account, lead_stage: active_stage, source: 'lp-auxilio-acidente')
    get url, headers: agent.create_new_auth_token, as: :json
    block = response.parsed_body['today']['new_from_lp']
    expect(block['count']).to eq(1)
    expect(block['items'].first['source']).to eq('lp-auxilio-acidente')
  end

  it 'rola o histórico de 30 dias somando só etapas abertas' do
    open_stage = account.lead_stages.find_by(name: 'Novo')
    won_stage = account.lead_stages.find_by(is_won: true)
    FunnelSnapshot.create!(account: account, snapshot_date: 2.days.ago.to_date,
                           lead_stage: open_stage, stage_name: 'Novo', stage_position: 0,
                           is_won: false, is_lost: false, leads_count: 4, value_sum: 4000)
    FunnelSnapshot.create!(account: account, snapshot_date: 2.days.ago.to_date,
                           lead_stage: won_stage, stage_name: 'Fechado', stage_position: 5,
                           is_won: true, is_lost: false, leads_count: 9, value_sum: 90_000)

    get url, headers: agent.create_new_auth_token, as: :json

    history = response.parsed_body['history']
    row = history.find { |h| h['date'] == 2.days.ago.to_date.to_s }
    expect(row['leads_count']).to eq(4)
    expect(row['value_sum']).to eq(4000.0)
  end

  it 'expõe o NPS (média e nº de respostas) na semana' do
    create(:lead, account: account, lead_stage: active_stage, custom_attributes: { 'nps' => { 'score' => 10 } })
    create(:lead, account: account, lead_stage: active_stage, custom_attributes: { 'nps' => { 'score' => 7 } })
    create(:lead, account: account, lead_stage: active_stage) # sem score não entra na conta
    get url, headers: agent.create_new_auth_token, as: :json
    nps = response.parsed_body['week']['nps']
    expect(nps['media']).to eq(8.5)
    expect(nps['respostas']).to eq(2)
  end

  it 'sem nenhuma resposta o NPS vem com média nula' do
    get url, headers: agent.create_new_auth_token, as: :json
    nps = response.parsed_body['week']['nps']
    expect(nps['media']).to be_nil
    expect(nps['respostas']).to eq(0)
  end

  it 'conta na meta do dia só as atividades esteira_done de hoje' do
    lead = create(:lead, account: account, lead_stage: active_stage)
    lead.lead_activities.create!(account: account, kind: 'esteira_done')
    lead.lead_activities.create!(account: account, kind: 'esteira_done', created_at: 2.days.ago)
    get url, headers: agent.create_new_auth_token, as: :json
    goal = response.parsed_body['goal']
    expect(goal['target']).to eq(12)
    expect(goal['done']).to eq(1)
  end

  it 'soma a previsão ponderada só das etapas abertas' do
    won_stage = account.lead_stages.find_by(is_won: true)
    create(:lead, account: account, lead_stage: active_stage, value: 1000) # Novo, probability 10
    create(:lead, account: account, lead_stage: won_stage, value: 5000)    # ganho fica fora
    get url, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['forecast_total']).to eq(100.0)
  end

  it 'mede a conversão etapa→etapa na janela de 90 dias' do
    qualificacao = account.lead_stages.find_by(name: 'Qualificação')
    advanced_lead = create(:lead, account: account, lead_stage: qualificacao)
    stuck_lead = create(:lead, account: account, lead_stage: qualificacao)
    advanced_lead.lead_activities.create!(account: account, kind: 'stage_changed', to_value: 'Qualificação', created_at: 3.days.ago)
    advanced_lead.lead_activities.create!(account: account, kind: 'stage_changed', to_value: 'Reunião agendada', created_at: 2.days.ago)
    stuck_lead.lead_activities.create!(account: account, kind: 'stage_changed', to_value: 'Qualificação', created_at: 3.days.ago)
    get url, headers: agent.create_new_auth_token, as: :json
    row = response.parsed_body['conversion'].find { |r| r['name'] == 'Qualificação' }
    expect(row['entered']).to eq(2)
    expect(row['advanced']).to eq(1)
    expect(row['rate']).to eq(50)
  end

  it 'ranqueia o time da semana por valor ganho, com fallback pro SDR' do
    won_stage = account.lead_stages.find_by(is_won: true)
    closer = create(:user, account: account, role: :agent)
    sdr = create(:user, account: account, role: :agent)
    create(:lead, account: account, lead_stage: won_stage, value: 3000, closer: closer)
    create(:lead, account: account, lead_stage: won_stage, value: 1000, sdr: sdr)
    get url, headers: agent.create_new_auth_token, as: :json
    team = response.parsed_body['team_week']
    expect(team.first['user_id']).to eq(closer.id)
    expect(team.first['won_value']).to eq(3000.0)
    expect(team.map { |r| r['user_id'] }).to include(sdr.id)
  end

  it 'lista só as reuniões de hoje na agenda' do
    lead = create(:lead, account: account, lead_stage: active_stage, source: 'lp-auxilio-acidente')
    create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'Reunião de amanhã', due_at: 1.day.from_now)
    create(:lead_task, account: account, lead: lead, title: 'Follow-up de hoje', due_at: Time.current)
    create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'Reunião de fechamento', due_at: Time.current, user: agent)
    get url, headers: agent.create_new_auth_token, as: :json
    agenda = response.parsed_body['agenda_today']
    expect(agenda.size).to eq(1)
    expect(agenda.first['title']).to eq('Reunião de fechamento')
    expect(agenda.first['lead_name']).to eq(lead.name)
    expect(agenda.first['user_name']).to eq(agent.name)
    expect(agenda.first['source']).to eq('lp-auxilio-acidente')
  end

  it 'agrupa as perdas por tese com motivos e trimestre anterior' do
    lost_stage = account.lead_stages.find_by(is_lost: true)
    thesis = account.theses.first || create(:thesis, account: account)
    create(:lead, account: account, lead_stage: lost_stage, thesis: thesis, lost_reason: 'Honorário')
    create(:lead, account: account, lead_stage: lost_stage, thesis: thesis, lost_reason: 'Honorário')
    create(:lead, account: account, lead_stage: lost_stage, lost_reason: 'Sumiu')
    create(:lead, account: account, lead_stage: lost_stage, thesis: thesis)
      .update_column(:lost_at, 120.days.ago) # rubocop:disable Rails/SkipsModelValidations
    get url, headers: agent.create_new_auth_token, as: :json
    block = response.parsed_body['losses_by_thesis']
    expect(block['window_days']).to eq(90)
    row = block['theses'].find { |t| t['thesis_id'] == thesis.id }
    expect(row['total']).to eq(2)
    expect(row['prev_total']).to eq(1)
    expect(row['reasons'].first).to eq('reason' => 'Honorário', 'count' => 2)
    sem_tese = block['theses'].find { |t| t['thesis_id'].nil? }
    expect(sem_tese['name']).to eq('Sem tese')
    expect(sem_tese['total']).to eq(1)
  end

  it 'mede o SLA de 1ª resposta de hoje nas inboxes de lead' do
    travel_to Time.utc(2026, 7, 22, 15, 0, 0) do # 12h em São Paulo — longe da virada do dia
      inbox = create(:inbox, account: account, auto_create_lead: true)
      breached = create(:conversation, account: account, inbox: inbox)
      breached.update_columns(created_at: 2.hours.ago) # rubocop:disable Rails/SkipsModelValidations
      replied = create(:conversation, account: account, inbox: inbox)
      replied.update_columns(created_at: 30.minutes.ago, first_reply_created_at: 20.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
      get url, headers: agent.create_new_auth_token, as: :json
      sla = response.parsed_body['sla_today']
      expect(sla['breached']).to eq(1)
      expect(sla['avg_first_response_minutes']).to eq(10.0)
    end
  end

  it 'respeita o SLA da própria inbox quando definido (COALESCE por conversa)' do
    travel_to Time.utc(2026, 7, 22, 15, 0, 0) do # 12h em São Paulo — longe da virada do dia
      inbox = create(:inbox, account: account, auto_create_lead: true, first_response_sla_minutes: 60)
      waiting = create(:conversation, account: account, inbox: inbox)
      waiting.update_columns(created_at: 30.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
      get url, headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['sla_today']['breached']).to eq(0)
    end
  end

  it 'sem conversa respondida hoje a média de 1ª resposta vem nula' do
    get url, headers: agent.create_new_auth_token, as: :json
    sla = response.parsed_body['sla_today']
    expect(sla['breached']).to eq(0)
    expect(sla['avg_first_response_minutes']).to be_nil
  end

  describe 'seção tv (Placar de TV)' do
    let(:won_stage) { account.lead_stages.find_by(is_won: true) }
    let(:thesis) { account.theses.first || create(:thesis, account: account) }
    let(:closer) { create(:user, account: account, role: :agent) }
    let(:benefit) { account.benefit_types.find_or_create_by!(name: 'Auxílio-acidente') }
    let!(:won) do
      create(:lead, account: account, lead_stage: won_stage, value: 30_000,
                    closer: closer, thesis: thesis, benefit_type: benefit)
    end
    let!(:meeting) do
      create(:lead_task, account: account, lead: won, kind: 'meeting',
                         title: 'Fechamento', due_at: 2.hours.from_now, user: closer)
    end

    before do
      create(:lead, account: account, lead_stage: active_stage, thesis: thesis,
                    dcb_em: 10.years.ago.to_date, benefit_monthly_value: 1412)
      create(:lead, account: account, lead_stage: active_stage) # sem tese
      get url, headers: agent.create_new_auth_token, as: :json
    end

    it 'soma o mês (sem meta por padrão) e o placar de hoje' do
      tv = response.parsed_body['tv']
      expect(tv['month']['won_value']).to eq(30_000.0)
      expect(tv['month']['won_count']).to eq(1)
      expect(tv['month']['goal']).to eq(0.0)
      expect(tv['month']['business_days_left']).to be_between(0, 23) # 0 só se o mês acabar num fim de semana
      expect(tv['month']['today']['won_count']).to eq(1)
      expect(tv['month']['today']['new_count']).to eq(3)
    end

    it 'quebra por tese com conversão do mês e prescrição' do
      row = response.parsed_body['tv']['by_thesis'].find { |r| r['thesis_id'] == thesis.id }
      expect(row['leads_count']).to eq(1) # só o aberto; o ganho não é lead aberto
      expect(row['new_week']).to eq(2)
      expect(row['won_month']).to eq(1)
      expect(row['won_value_month']).to eq(30_000.0)
      expect(row['conversion_pct']).to eq(100)
      expect(row['prescribing_count']).to eq(1)
      expect(row['prescribing_monthly']).to eq(1412.0)
    end

    it 'agrupa lead sem tese em "Sem tese"' do
      sem_tese = response.parsed_body['tv']['by_thesis'].find { |r| r['thesis_id'].nil? }
      expect(sem_tese['name']).to eq('Sem tese')
      expect(sem_tese['leads_count']).to eq(1)
    end

    it 'expõe corrida, prescrição total, próximo compromisso e último ganho' do
      tv = response.parsed_body['tv']
      expect(tv['race'].first).to include('name' => closer.name, 'won_count' => 1, 'won_value' => 30_000.0)
      expect(tv['prescribing_total_monthly']).to eq(1412.0)
      expect(tv['next_meeting']).to include('lead_name' => won.name, 'user_name' => closer.name)
      expect(Time.zone.parse(tv['next_meeting']['at'])).to be_within(1.minute).of(meeting.due_at)
      expect(tv['last_won']).to include('lead_name' => won.name, 'closer_name' => closer.name,
                                        'value' => 30_000.0, 'benefit' => 'Auxílio-acidente')
    end
  end

  describe 'seção tv sem fechamento no mês' do
    let(:thesis) { account.theses.first || create(:thesis, account: account) }

    it 'lê a meta mensal do env e devolve conversão nula sem fechamento' do
      create(:lead, account: account, lead_stage: active_stage, thesis: thesis)
      with_modified_env RAMON_MONTHLY_GOAL_BRL: '400000' do
        get url, headers: agent.create_new_auth_token, as: :json
      end
      tv = response.parsed_body['tv']
      expect(tv['month']['goal']).to eq(400_000.0)
      row = tv['by_thesis'].find { |r| r['thesis_id'] == thesis.id }
      expect(row['conversion_pct']).to be_nil
      expect(tv['last_won']).to be_nil
      expect(tv['next_meeting']).to be_nil
      expect(tv['race']).to eq([])
    end
  end

  it 'denies a user without access to the account' do
    stranger = create(:user)
    get url, headers: stranger.create_new_auth_token, as: :json
    expect(response).not_to have_http_status(:success)
    expect(response).to have_http_status(:unauthorized).or have_http_status(:not_found)
  end
end
