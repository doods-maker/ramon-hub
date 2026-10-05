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

  describe 'PATCH (Remarcar)' do
    let(:novo_horario) { 4.days.from_now.change(usec: 0) }

    def remarcar(task, params = {})
      patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}/reuniao_agendada",
            params: { task_id: task.id, starts_at: novo_horario.iso8601 }.merge(params), headers: agent.create_new_auth_token, as: :json
    end

    it 'remarca a reunião e devolve a tarefa no horário novo', :aggregate_failures do
      agendar(starts_at: starts_at.iso8601)
      task = lead.lead_tasks.find_by!(kind: 'meeting')
      remarcar(task)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).to eq task.id
      expect(Time.zone.parse(response.parsed_body['due_at'])).to eq novo_horario
      expect(lead.lead_activities.where(kind: 'meeting_rescheduled')).to exist
    end

    it 'não remarca tarefa que não é reunião' do
      task = create(:lead_task, account: account, lead: lead, kind: 'follow_up')
      remarcar(task)
      expect(response).to have_http_status(:not_found)
    end

    it 'sem data/hora válida dá 422' do
      agendar(starts_at: starts_at.iso8601)
      remarcar(lead.lead_tasks.find_by!(kind: 'meeting'), starts_at: 'amanhã')
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'reunião já aberta' do
    before { agendar(starts_at: starts_at.iso8601) }

    it 'devolve 409 com a reunião aberta e não marca outra', :aggregate_failures do
      expect { agendar(starts_at: (starts_at + 1.day).iso8601) }.not_to change(LeadTask, :count)
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['task']['id']).to eq lead.lead_tasks.find_by!(kind: 'meeting').id
    end

    it 'com force=true marca mesmo assim' do
      expect { agendar(starts_at: (starts_at + 1.day).iso8601, force: true) }.to change(LeadTask, :count).by(1)
    end
  end

  describe 'DELETE (Cancelar)' do
    it 'cancela a reunião aberta', :aggregate_failures do
      agendar(starts_at: starts_at.iso8601)
      task = lead.lead_tasks.find_by!(kind: 'meeting')
      delete "/api/v1/accounts/#{account.id}/leads/#{lead.id}/reuniao_agendada",
             params: { task_id: task.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(LeadTask.exists?(task.id)).to be(false)
      expect(lead.lead_activities.where(kind: 'meeting_cancelled')).to exist
    end
  end
end
