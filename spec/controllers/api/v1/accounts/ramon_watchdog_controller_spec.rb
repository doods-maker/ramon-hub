require 'rails_helper'

RSpec.describe 'Ramon Watchdog API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_watchdog" }
  let(:stage) { account.lead_stages.find_by(is_won: false, is_lost: false) }

  before { stage.update!(stalled_after_days: 3) }

  it 'lista os casos parados, com quem ja levou mais retomada na frente' do
    parado = create(:lead, account: account, lead_stage: stage, name: 'Parado')
    insistido = create(:lead, account: account, lead_stage: stage, name: 'Insistido',
                              custom_attributes: { 'follow_up' => { 'tentativas' => 2, 'ultima_em' => 2.days.ago.iso8601 } })
    # rubocop:disable Rails/SkipsModelValidations
    # stage_entered_at é reescrito pelo before_save do Lead — só update_all deixa o lead "parado" no passado.
    Lead.where(id: [parado.id, insistido.id]).update_all(stage_entered_at: 10.days.ago)
    # rubocop:enable Rails/SkipsModelValidations

    get url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['items'].pluck('lead_id')).to eq([insistido.id, parado.id])
    expect(body['items'].first).to include('tentativas' => 2, 'dias_parado' => 10)
    expect(body['thresholds']).to include('teto_diario' => Ramon::FollowUpDraftService::DAILY_CAP)
    expect(body['counters']).to include('parados_agora' => 2)
  end

  it 'conta as retomadas e as sugestoes das ultimas 24h' do
    lead = create(:lead, account: account, lead_stage: stage)
    create(:lead_task, account: account, lead: lead, kind: 'follow_up', title: 'Retomada nº 1')
    account.copilot_suggestions.create!(lead: lead, kind: 'draft', status: 'pending', payload: { 'texto' => 'oi' })

    get url, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['counters']).to include('retomadas_24h' => 1, 'sugestoes_pendentes' => 1)
  end

  it 'exige autenticacao' do
    get url, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
