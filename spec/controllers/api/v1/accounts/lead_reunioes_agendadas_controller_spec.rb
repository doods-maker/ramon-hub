require 'rails_helper'

RSpec.describe 'Lead Reunião Agendada API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:novo) { account.lead_stages.order(:position).first }
  let(:lead) { create(:lead, account: account, lead_stage: novo) }
  let(:starts_at) { 2.days.from_now.change(usec: 0) }

  def agendar(params, headers = agent.create_new_auth_token)
    post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/reuniao_agendada", params: params, headers: headers, as: :json
  end

  it 'sem login responde 401' do
    agendar({ starts_at: starts_at.iso8601 }, {})
    expect(response).to have_http_status(:unauthorized)
  end

  it 'marca a reunião pelo painel e devolve o lead já em Reunião agendada', :aggregate_failures do
    agendar(starts_at: starts_at.iso8601, title: 'Reunião com João')

    expect(response).to have_http_status(:success)
    agendada = account.lead_stages.find_by!(label: 'fase-reuniao-agendada')
    expect(response.parsed_body['lead_stage_id']).to eq agendada.id
    task = lead.lead_tasks.find_by!(kind: 'meeting')
    expect(task.title).to eq 'Reunião com João'
    expect(task.due_at).to eq starts_at
    expect(lead.lead_notes.where("body LIKE 'RASCUNHO%'")).to exist
  end

  it 'sem título usa "Reunião"' do
    agendar(starts_at: starts_at.iso8601)
    expect(lead.lead_tasks.find_by!(kind: 'meeting').title).to eq 'Reunião'
  end

  it 'sem data/hora válida dá 422 sem criar nada', :aggregate_failures do
    expect { agendar(starts_at: 'amanhã') }.not_to change(LeadTask, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
