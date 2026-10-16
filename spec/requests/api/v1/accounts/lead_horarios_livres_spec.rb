require 'rails_helper'

RSpec.describe 'Lead horários livres API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:closer) { create(:user, account: account, role: :agent) }
  let(:lead) { create(:lead, account: account, closer: closer) }
  let(:base) { "/api/v1/accounts/#{account.id}/leads" }
  let(:inicio) { Time.find_zone!('America/Sao_Paulo').local(2026, 10, 22, 14, 0) }

  def stub_livres(horarios)
    disp = instance_double(Ramon::Agenda::Disponibilidade, livres: horarios)
    allow(Ramon::Agenda::Disponibilidade).to receive(:new).with(user: closer, account: account).and_return(disp)
  end

  it 'devolve os horários livres do Closer e o texto' do
    stub_livres([inicio, inicio + 1.hour])
    get "#{base}/#{lead.id}/horarios_livres", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['horarios']).to eq([inicio.iso8601, (inicio + 1.hour).iso8601])
    expect(response.parsed_body['texto']).to include('14:00 ou 15:00')
  end

  it 'sem horários devolve lista e texto vazios' do
    stub_livres([])
    get "#{base}/#{lead.id}/horarios_livres", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to eq('horarios' => [], 'texto' => '')
  end

  it 'lead de outra conta é 404' do
    outro = create(:lead, account: create(:account))
    get "#{base}/#{outro.id}/horarios_livres", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end
end
