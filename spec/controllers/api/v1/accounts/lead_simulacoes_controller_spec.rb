require 'rails_helper'

RSpec.describe 'Lead Simulacoes API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:thesis) { create(:thesis, account: account, honorario_percentual: 30, honorario_n_mensalidades: 3) }
  let(:lead) { create(:lead, account: account, thesis: thesis) }
  let(:der) { 10.months.ago.to_date }
  let(:simulacao_params) do
    { nascimento: '1980-05-10', sexo: 'M', der: der.iso8601, salario: '3000.00',
      beneficio: 'acidente', origem: 'acidentaria', acrescimo_25: false }
  end
  let(:motor_url) { 'http://motor:8000' }
  let(:motor_body) do
    { beneficio: 'acidente', sb: '3200.00', percentual: '0.5', rmi: '1600.00',
      valor_hoje: '1700.00', memoria: {}, avisos: ['qualidade de segurado não é aferida pelo motor'] }.to_json
  end

  def simulate(headers = admin.create_new_auth_token)
    post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/simulacao",
         params: simulacao_params, headers: headers, as: :json
  end

  def doze_competencias?(competencias)
    competencias.length == 12 && competencias.all? { |c| c['salario'] == '3000.00' }
  end

  it 'returns unauthorized without auth' do
    simulate({})
    expect(response).to have_http_status(:unauthorized)
  end

  context 'when the motor responds' do
    before do
      stub_request(:post, "#{motor_url}/incapacidade")
        .to_return(status: 200, body: motor_body, headers: { 'Content-Type' => 'application/json' })
    end

    it 'returns mensal, perda mensal and estimated atrasados' do
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        simulate
      end
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['mensal']).to eq('1700.00')
      expect(body['perda_mensal']).to eq('1700.00')
      expect(body['atrasados']).to eq('17000.00')
      expect(body['atrasados_estimativa']).to include('estimado' => true, 'meses' => 10)
      expect(body['avisos']).to include('qualidade de segurado não é aferida pelo motor')
    end

    it 'applies the honorario formula from the lead thesis' do
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        simulate
      end
      # 30% × 17000.00 + 3 × 1700.00 = 5100.00 + 5100.00
      expect(response.parsed_body['honorario']).to include(
        'valor' => '10200.00', 'percentual' => 30.0, 'n_mensalidades' => 3, 'tese' => thesis.name
      )
    end

    it 'sends 12 competencias with the average salary to the motor' do
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        simulate
      end
      matcher = have_requested(:post, "#{motor_url}/incapacidade")
                .with { |req| doze_competencias?(JSON.parse(req.body)['competencias']) }
      expect(WebMock).to matcher
    end

    it 'flags when the lead thesis has no honorario config' do
      lead.update!(thesis: create(:thesis, account: account, name: 'Sem honorário'))
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        simulate
      end
      expect(response.parsed_body['honorario']['valor']).to be_nil
      expect(response.parsed_body['honorario']['motivo']).to be_present
    end
  end

  it 'returns unprocessable entity when the motor rejects the input' do
    stub_request(:post, "#{motor_url}/incapacidade")
      .to_return(status: 422, body: { detail: 'benefício inválido' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    with_modified_env MOTOR_CALCULOS_URL: motor_url do
      simulate
    end
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('benefício inválido')
  end

  it 'returns service unavailable when the motor is down' do
    stub_request(:post, "#{motor_url}/incapacidade").to_raise(Errno::ECONNREFUSED)
    with_modified_env MOTOR_CALCULOS_URL: motor_url do
      simulate
    end
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body['error']).to include('motor indisponível')
  end

  it 'returns service unavailable when MOTOR_CALCULOS_URL is not set' do
    with_modified_env MOTOR_CALCULOS_URL: nil do
      simulate
    end
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body['error']).to include('MOTOR_CALCULOS_URL')
  end
end
