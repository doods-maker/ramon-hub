require 'rails_helper'

RSpec.describe 'Lead Paineis API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:lead) { create(:lead, account: account) }
  let(:motor_url) { 'http://motor:8000' }
  let(:motor_body) do
    { resumo: { tempo_contribuicao: '34a, 11m e 3d', carencia: 425 },
      cartoes: [{ id: 'idade_pre', elegivel: false, rmi: '3396.58' }],
      avisos: [] }.to_json
  end
  let(:painel_params) do
    { nascimento: '1968-08-07', sexo: 'M', der: '2026-06-30',
      vinculos_extras: [
        { inicio: '1980-08-07', fim: '1988-04-30', tipo: 'EMPREGO' },
        { inicio: '2020-01-01', fim: '2020-03-31', tipo: 'RECOLHIMENTO', salario: '2000.00' }
      ] }
  end

  def calcular(params = painel_params, headers = admin.create_new_auth_token)
    post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/painel",
         params: params, headers: headers, as: :json
  end

  it 'returns unauthorized without auth' do
    calcular(painel_params, {})
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects an invalid der' do
    calcular(painel_params.merge(der: '30/06/2026'))
    expect(response).to have_http_status(:unprocessable_entity)
  end

  context 'when the motor responds' do
    before do
      stub_request(:post, "#{motor_url}/painel")
        .to_return(status: 200, body: motor_body, headers: { 'Content-Type' => 'application/json' })
    end

    it 'proxies the painel with manual vinculos (tempo only + with salary)' do
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        calcular
      end
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['cartoes'].first['id']).to eq('idade_pre')
      matcher = have_requested(:post, "#{motor_url}/painel").with do |req|
        body = JSON.parse(req.body)
        body['segurado'] == { 'nascimento' => '1968-08-07', 'sexo' => 'M' } &&
          body['vinculos'].length == 2 &&
          body['vinculos'].first == { 'inicio' => '1980-08-07', 'fim' => '1988-04-30',
                                      'tipo' => 'EMPREGO', 'indicadores' => [] } &&
          # só o vínculo com salário vira competências (3 meses × 2000.00)
          body['competencias'] == [
            { 'ano' => 2020, 'mes' => 1, 'salario' => '2000.00' },
            { 'ano' => 2020, 'mes' => 2, 'salario' => '2000.00' },
            { 'ano' => 2020, 'mes' => 3, 'salario' => '2000.00' }
          ]
      end
      expect(WebMock).to matcher
    end

    it 'combines the stored CNIS with the manual vinculos' do
      lead.update!(cnis: {
                     'entrada' => {
                       'segurado' => { 'nascimento' => '1975-01-20', 'sexo' => 'F' },
                       'competencias' => [{ 'ano' => 2023, 'mes' => 5, 'salario' => '2500.00' }],
                       'vinculos' => [{ 'inicio' => '2023-05-01', 'fim' => '2023-05-31',
                                        'tipo' => 'EMPREGO', 'indicadores' => [] }]
                     }
                   })
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        calcular
      end
      matcher = have_requested(:post, "#{motor_url}/painel").with do |req|
        body = JSON.parse(req.body)
        body['segurado'] == { 'nascimento' => '1975-01-20', 'sexo' => 'F' } &&
          body['vinculos'].length == 3 &&
          body['competencias'].first == { 'ano' => 2023, 'mes' => 5, 'salario' => '2500.00' } &&
          body['competencias'].length == 4
      end
      expect(WebMock).to matcher
    end

    it 'drops manual vinculos with invalid dates' do
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        calcular(painel_params.merge(vinculos_extras: [{ inicio: '2020-01-01', fim: '2019-01-01' }]))
      end
      matcher = have_requested(:post, "#{motor_url}/painel")
                .with { |req| JSON.parse(req.body)['vinculos'].empty? }
      expect(WebMock).to matcher
    end
  end

  context 'with tempo especial (especiais)' do
    it 'funde especiais nos vinculos por seq e persiste nos parametros' do
      lead.update!(cnis: {
                     'entrada' => {
                       'segurado' => { 'nascimento' => '1975-01-20', 'sexo' => 'F' },
                       'competencias' => [],
                       'vinculos' => [{ 'seq' => 3, 'inicio' => '2010-01-01', 'fim' => '2015-12-31',
                                        'tipo' => 'EMPREGO', 'indicadores' => [] }]
                     }
                   })
      corpo_enviado = nil
      stub_request(:post, "#{motor_url}/painel").with { |req| corpo_enviado = JSON.parse(req.body); true }
        .to_return(status: 200, body: { resumo: {}, cartoes: [], avisos: [] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        calcular(painel_params.merge(vinculos_extras: [], especiais: { '3' => { 'grau' => 25 } }.to_json))
      end

      expect(response).to have_http_status(:success)
      v3 = corpo_enviado['vinculos'].find { |v| v['seq'] == 3 }
      expect(v3['especial']).to eq('grau' => 25, 'inicio' => nil, 'fim' => nil)
      expect(lead.reload.cnis.dig('parametros', 'especiais')).to be_present
    end

    it 'passa especial dos vinculos_extras adiante' do
      corpo_enviado = nil
      stub_request(:post, "#{motor_url}/painel").with { |req| corpo_enviado = JSON.parse(req.body); true }
        .to_return(status: 200, body: { resumo: {}, cartoes: [], avisos: [] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        calcular(painel_params.merge(vinculos_extras: [
                                        { inicio: '2005-01-01', fim: '2010-01-01', tipo: 'EMPREGO',
                                          especial: { grau: 15 } }
                                      ]))
      end

      expect(response).to have_http_status(:success)
      extra = corpo_enviado['vinculos'].find { |v| v['inicio'] == '2005-01-01' }
      expect(extra['especial']).to eq('grau' => 15, 'inicio' => nil, 'fim' => nil)
    end

    it 'especiais invalido (JSON quebrado) devolve 422 sem 500' do
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        calcular(painel_params.merge(especiais: '{nao-e-json'))
      end
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to be_present
    end
  end

  it 'returns unprocessable entity when the motor rejects the input' do
    stub_request(:post, "#{motor_url}/painel")
      .to_return(status: 422, body: { detail: 'histórico sem salários no PBC' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    with_modified_env MOTOR_CALCULOS_URL: motor_url do
      calcular
    end
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('histórico sem salários no PBC')
  end

  it 'returns service unavailable when the motor is down' do
    stub_request(:post, "#{motor_url}/painel").to_raise(Errno::ECONNREFUSED)
    with_modified_env MOTOR_CALCULOS_URL: motor_url do
      calcular
    end
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body['error']).to include('motor indisponível')
  end
end
