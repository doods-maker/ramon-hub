require 'rails_helper'

RSpec.describe 'Public Agenda ICS', type: :request do
  let(:account) { create(:account) }
  let(:lead) { create(:lead, account: account, name: 'Maria das Dores') }
  let(:task) do
    create(:lead_task, account: account, lead: lead, kind: 'meeting', due_at: Time.zone.parse('2026-10-20T10:00:00-03:00'),
                       meet_url: 'https://meet.google.com/abc-defg')
  end

  it 'devolve o .ics da reunião, só com o evento', :aggregate_failures do
    get "/public/api/v1/agenda/#{task.signed_id(purpose: :ics, expires_in: 60.days)}.ics"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq 'text/calendar'
    expect(response.body).to include('BEGIN:VCALENDAR', 'DTSTART:20261020T130000Z', 'SUMMARY:Conversa com Ramon Antonio Advogados')
    expect(response.body).not_to include('Maria')
  end

  it 'token inválido é 404' do
    get '/public/api/v1/agenda/lixo.ics'
    expect(response).to have_http_status(:not_found)
  end

  it 'token vencido é 404' do
    token = task.signed_id(purpose: :ics, expires_in: 60.days)
    travel_to(61.days.from_now) { get "/public/api/v1/agenda/#{token}.ics" }
    expect(response).to have_http_status(:not_found)
  end

  it 'token de outro propósito é 404' do
    get "/public/api/v1/agenda/#{task.signed_id(purpose: :outro)}.ics"
    expect(response).to have_http_status(:not_found)
  end
end
