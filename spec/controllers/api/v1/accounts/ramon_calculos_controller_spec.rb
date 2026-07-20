require 'rails_helper'

RSpec.describe 'Ramon Calculos API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  around do |example|
    with_modified_env(ADVBOX_API_TOKEN: 'tok') { example.run }
  end

  describe 'GET /advbox_customers' do
    let(:url) { "/api/v1/accounts/#{account.id}/ramon_calculos/advbox_customers" }

    it 'exige login' do
      get url, params: { q: 'Silva' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'busca por nome e devolve payload enxuto' do
      stub = stub_request(:get, 'https://app.advbox.com.br/api/v1/customers')
             .with(query: hash_including('name' => 'Silva'))
             .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                        body: { data: [{ 'id' => 9, 'name' => 'João Silva', 'identification' => '52998224725',
                                         'cellphone' => '48999887766', 'birthdate' => '1980-05-10',
                                         'protocol_number' => 'nao-vaza' }] }.to_json)
      get url, params: { q: 'Silva' }, headers: agent.create_new_auth_token, as: :json
      expect(stub).to have_been_requested
      item = response.parsed_body['payload'].sole
      expect(item).to eq('id' => 9, 'name' => 'João Silva', 'identification' => '52998224725',
                         'cellphone' => '48999887766', 'birthdate' => '1980-05-10', 'email' => nil)
    end

    it 'q com 11 dígitos vira busca por CPF (identification)' do
      stub = stub_request(:get, 'https://app.advbox.com.br/api/v1/customers')
             .with(query: hash_including('identification' => '52998224725'))
             .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                        body: { data: [] }.to_json)
      get url, params: { q: '529.982.247-25' }, headers: agent.create_new_auth_token, as: :json
      expect(stub).to have_been_requested
      expect(response.parsed_body['payload']).to eq([])
    end

    it 'AdvBox fora do ar vira 503 com erro nomeado' do
      stub_request(:get, 'https://app.advbox.com.br/api/v1/customers')
        .with(query: hash_including('name' => 'Silva')).to_timeout
      get url, params: { q: 'Silva' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body['error']).to eq('ADVBOX_UNAVAILABLE')
    end
  end

  describe 'POST /criar_caso' do
    let(:url) { "/api/v1/accounts/#{account.id}/ramon_calculos/criar_caso" }

    it 'exige login' do
      post url, params: { nome: 'João' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'cria caso a partir de dados do AdvBox e devolve o lead' do
      post url, params: { nome: 'João Silva', cpf: '529.982.247-25' },
                headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      lead = response.parsed_body['leads'].sole
      expect(lead['source']).to eq(Lead::FONTE_CALCULO)
      expect(response.parsed_body.dig('contact', 'name')).to eq('João Silva')
    end

    it 'com contact_id cria caso pro contato sem lead' do
      contact = create(:contact, account: account)
      post url, params: { contact_id: contact.id },
                headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body.dig('contact', 'id')).to eq(contact.id)
      expect(response.parsed_body['leads'].sole['contact_id']).to eq(contact.id)
    end
  end
end
