require 'rails_helper'

RSpec.describe 'Lead CNIS API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:lead) { create(:lead, account: account) }
  let(:motor_url) { 'http://motor:8000' }
  let(:arquivo) { Rack::Test::UploadedFile.new('spec/assets/sample.pdf', 'application/pdf') }
  let(:motor_body) do
    {
      entrada_calcular: {
        segurado: { nascimento: '1980-05-10', sexo: 'M' },
        competencias: [{ ano: 2024, mes: 1, salario: '3000.00' }, { ano: 2024, mes: 2, salario: '3100.00' }],
        vinculos: [{ inicio: '2020-01-01', fim: nil, tipo: 'EMPREGO', indicadores: [] }]
      },
      vinculos: [{ seq: 1, tipo: 'EMPREGO', origem: 'ACME LTDA' }],
      avisos: [
        { gravidade: 'atencao', alvo: '03/2013', sigla: 'IREC', mensagem: 'indicador pendente' },
        { gravidade: 'atencao', alvo: '', sigla: '', mensagem: 'tabela de correção defasada' }
      ]
    }.to_json
  end

  def upload(headers = admin.create_new_auth_token)
    post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/cnis",
         params: { arquivo: arquivo, sexo: 'M' }, headers: headers
  end

  it 'returns unauthorized without auth' do
    upload({})
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns unprocessable entity without the file' do
    post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/cnis",
         params: { sexo: 'M' }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('arquivo')
  end

  context 'when the motor parses the PDF' do
    before do
      stub_request(:post, "#{motor_url}/cnis")
        .to_return(status: 200, body: motor_body, headers: { 'Content-Type' => 'application/json' })
    end

    it 'stores the parsed CNIS on the lead and returns the resumo' do
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        upload
      end
      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include(
        'filename' => 'sample.pdf', 'nascimento' => '1980-05-10', 'competencias' => 2, 'vinculos' => 1
      )
      expect(response.parsed_body['avisos']).to eq(['03/2013: indicador pendente', 'tabela de correção defasada'])
      expect(lead.reload.cnis.dig('entrada', 'competencias').length).to eq(2)
    end
  end

  it 'returns unprocessable entity when the motor rejects the PDF' do
    stub_request(:post, "#{motor_url}/cnis")
      .to_return(status: 422, body: { detail: 'PDF acima de 20MB' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    with_modified_env MOTOR_CALCULOS_URL: motor_url do
      upload
    end
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('PDF acima de 20MB')
  end

  it 'returns service unavailable when the motor is down' do
    stub_request(:post, "#{motor_url}/cnis").to_raise(Errno::ECONNREFUSED)
    with_modified_env MOTOR_CALCULOS_URL: motor_url do
      upload
    end
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body['error']).to include('motor indisponível')
  end

  describe 'DELETE' do
    it 'clears the stored CNIS' do
      lead.update!(cnis: { 'filename' => 'antigo.pdf' })
      delete "/api/v1/accounts/#{account.id}/leads/#{lead.id}/cnis",
             headers: admin.create_new_auth_token
      expect(response).to have_http_status(:no_content)
      expect(lead.reload.cnis).to be_nil
    end
  end
end
