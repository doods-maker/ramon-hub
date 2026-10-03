require 'rails_helper'

RSpec.describe 'Ramon Busca API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_busca" }

  it 'exige login' do
    get url, params: { q: 'joao' }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'devolve os três grupos pro agente' do
    lead = create(:lead, account: account, name: 'João Pedro Martins')
    get url, params: { q: 'joao' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['leads'].pluck('id')).to eq([lead.id])
    expect(response.parsed_body).to include('clientes' => [], 'processos' => [])
  end
end
