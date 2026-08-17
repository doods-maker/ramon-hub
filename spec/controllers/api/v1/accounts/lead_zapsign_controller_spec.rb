require 'rails_helper'

RSpec.describe 'Lead ZapSign API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:lead) { create(:lead, account: account) }

  # perform consulta os modelos pra gravar 'template_name' — sem stub o WebMock
  # barra o GET /templates/ e o erro não cai nos rescues do controller.
  before { allow(Ramon::ZapsignClient).to receive(:templates).and_return([]) }

  def gerar(headers = admin.create_new_auth_token)
    post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/zapsign", headers: headers
  end

  it 'returns unauthorized without auth' do
    gerar({})
    expect(response).to have_http_status(:unauthorized)
  end

  it 'gera o contrato e devolve o link de assinatura' do
    stub_request(:post, 'https://api.zapsign.com.br/api/v1/models/create-doc/')
      .to_return(status: 200,
                 body: { 'token' => 'doc-123',
                         'signers' => [{ 'sign_url' => 'https://app.zapsign.com.br/verificar/abc' }] }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    with_modified_env(ZAPSIGN_API_TOKEN: 'tok') { gerar }

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['sign_url']).to eq('https://app.zapsign.com.br/verificar/abc')
  end

  it 'devolve service_unavailable sem token configurado' do
    with_modified_env(ZAPSIGN_API_TOKEN: nil) { gerar }
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body['error']).to include('ZAPSIGN_API_TOKEN')
  end

  it 'devolve unprocessable_entity quando o ZapSign recusa (4xx)' do
    stub_request(:post, 'https://api.zapsign.com.br/api/v1/models/create-doc/')
      .to_return(status: 400, body: { 'error' => 'template inválido' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    with_modified_env(ZAPSIGN_API_TOKEN: 'tok') { gerar }
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
