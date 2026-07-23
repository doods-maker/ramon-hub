require 'rails_helper'

RSpec.describe 'Copilot Suggestions API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:lead) { create(:lead, account: account) }

  it 'lists only pending suggestions with the lead name' do
    suggestion = create(:copilot_suggestion, account: account, lead: lead)
    create(:copilot_suggestion, account: account, lead: lead, status: 'dismissed')

    get "/api/v1/accounts/#{account.id}/copilot_suggestions",
        headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['payload'].pluck('id')).to eq([suggestion.id])
    expect(response.parsed_body['payload'].first['lead_name']).to eq(lead.name)
    expect(response.parsed_body).to have_key('reviewed_count')
  end

  it 'applies a draft: creates a RASCUNHO note and marks applied' do
    suggestion = create(:copilot_suggestion, account: account, lead: lead)

    expect do
      post "/api/v1/accounts/#{account.id}/copilot_suggestions/#{suggestion.id}/apply",
           headers: agent.create_new_auth_token, as: :json
    end.to change(lead.lead_notes, :count).by(1)

    expect(response).to have_http_status(:success)
    expect(lead.lead_notes.last.body).to start_with('RASCUNHO (revisar antes de enviar) — copiloto noturno:')
    expect(lead.lead_notes.last.body).to include('Oi, tudo bem?')
    expect(suggestion.reload.status).to eq('applied')
  end

  it 'applies a move_stage resolving the stage by name' do
    target = create(:lead_stage, account: account, name: 'Qualificado')
    suggestion = create(:copilot_suggestion, account: account, lead: lead, kind: 'move_stage',
                                             payload: { 'etapa_sugerida' => 'Qualificado' })

    post "/api/v1/accounts/#{account.id}/copilot_suggestions/#{suggestion.id}/apply",
         headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(lead.reload.lead_stage_id).to eq(target.id)
    expect(suggestion.reload.status).to eq('applied')
  end

  it 'does not apply move_stage when the suggested stage name does not resolve' do
    suggestion = create(:copilot_suggestion, account: account, lead: lead, kind: 'move_stage',
                                             payload: { 'etapa_sugerida' => 'Etapa Inexistente' })
    original_stage_id = lead.lead_stage_id

    post "/api/v1/accounts/#{account.id}/copilot_suggestions/#{suggestion.id}/apply",
         headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(lead.reload.lead_stage_id).to eq(original_stage_id)
    expect(suggestion.reload.status).to eq('pending')
  end

  it 'dismisses a suggestion' do
    suggestion = create(:copilot_suggestion, account: account, lead: lead)

    post "/api/v1/accounts/#{account.id}/copilot_suggestions/#{suggestion.id}/dismiss",
         headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(suggestion.reload.status).to eq('dismissed')
  end

  it 'apply_all applies drafts and alerts but never move_stage (bulk funnel change needs a human eye)' do
    draft = create(:copilot_suggestion, account: account, lead: lead)
    alerta = create(:copilot_suggestion, account: account, lead: lead, kind: 'alert',
                                         payload: { 'justificativa' => 'risco' })
    move = create(:copilot_suggestion, account: account, lead: lead, kind: 'move_stage',
                                       payload: { 'etapa_sugerida' => 'Qualquer' })

    post "/api/v1/accounts/#{account.id}/copilot_suggestions/apply_all",
         headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(draft.reload.status).to eq('applied')
    expect(alerta.reload.status).to eq('applied')
    expect(move.reload.status).to eq('pending')
    expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(draft.id, alerta.id)
  end

  it 'denies a user without access to the account' do
    stranger = create(:user)
    get "/api/v1/accounts/#{account.id}/copilot_suggestions",
        headers: stranger.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end
