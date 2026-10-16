require 'rails_helper'

RSpec.describe Ramon::Agenda::Convite do
  let(:account) { create(:account) }
  let(:closer) { create(:user, account: account, name: 'Dr. Eduardo') }
  let(:lead) { create(:lead, account: account, name: 'Maria das Dores', closer_id: closer.id) }
  let(:inicio) { Time.zone.parse('2026-10-20T10:00:00-03:00') }
  let(:task) do
    create(:lead_task, account: account, lead: lead, kind: 'meeting', due_at: inicio, formato: 'video', meet_url: 'https://meet.google.com/abc-defg')
  end
  let(:convite) { described_class.new(task) }

  def query(url) = Rack::Utils.parse_query(URI.parse(url).query)

  it 'link_google leva o título aprovado, as datas em UTC e o Meet', :aggregate_failures do
    url = convite.link_google
    expect(url).to start_with('https://calendar.google.com/calendar/render?action=TEMPLATE')
    expect(url).to include('dates=20261020T130000Z/20261020T133000Z')
    expect(query(url)).to include('text' => 'Conversa com Ramon Antonio Advogados', 'details' => 'Google Meet: https://meet.google.com/abc-defg')
  end

  it 'link_google de WhatsApp leva a ligação, sem Meet' do
    task.update!(formato: 'whatsapp', meet_url: nil)
    expect(query(convite.link_google)['details']).to eq 'Eu te ligo no WhatsApp nesse horário.'
  end

  it 'ics é um VCALENDAR válido, sem dados do cliente', :aggregate_failures do
    ics = convite.ics
    expect(ics).to start_with("BEGIN:VCALENDAR\r\n")
    expect(ics).to end_with("END:VCALENDAR\r\n")
    expect(ics).to include("UID:hub-#{task.id}", 'DTSTART:20261020T130000Z', 'DTEND:20261020T133000Z',
                           'SUMMARY:Conversa com Ramon Antonio Advogados', 'LOCATION:https://meet.google.com/abc-defg')
    expect(ics).not_to include('Maria')
  end

  it 'link_ics usa o signed_id da tarefa e volta a ela', :aggregate_failures do
    with_modified_env(FRONTEND_URL: 'https://hub.exemplo.com') do
      url = convite.link_ics
      expect(url).to start_with('https://hub.exemplo.com/public/api/v1/agenda/')
      expect(url).to end_with('.ics')
      token = url.delete_prefix('https://hub.exemplo.com/public/api/v1/agenda/').delete_suffix('.ics')
      expect(LeadTask.find_signed(token, purpose: :ics)).to eq task
    end
  end

  it 'descricao é o convite aprovado' do
    expect(convite.descricao).to start_with('Olá, Maria! Esta é a nossa conversa sobre o seu caso, com Dr. Eduardo.')
  end
end
