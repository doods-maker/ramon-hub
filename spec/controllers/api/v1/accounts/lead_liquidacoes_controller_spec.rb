require 'rails_helper'

RSpec.describe 'Lead Liquidacoes API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:lead) { create(:lead, account: account) }
  let(:motor_url) { 'http://motor:8000' }
  let(:motor_body) do
    { total_principal_corrigido: '98000.00', total_juros: '7000.00',
      total_atualizacao_selic_ec136: '0.00', total_geral: '105000.00',
      honorarios: { sucumbenciais: nil, contratuais: nil },
      liquido_cliente: '105000.00', memoria: [], avisos: [], parametros: {} }.to_json
  end
  let(:liquidacao_params) { { rmi: '1518.00', dib: '2022-03-10', data_citacao: '2023-05-02' } }

  def liquidar(params = liquidacao_params, headers = admin.create_new_auth_token, caminho = 'liquidacao')
    post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/#{caminho}",
         params: params, headers: headers, as: :json
  end

  it 'returns unauthorized without auth' do
    liquidar(liquidacao_params, {})
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects rmi ausente ou nao positiva com mensagem pt' do
    liquidar(liquidacao_params.merge(rmi: '0'))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('RMI')
  end

  it 'rejects dib invalida' do
    liquidar(liquidacao_params.merge(dib: '10/03/2022'))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('DIB')
  end

  it 'rejects data opcional invalida' do
    liquidar(liquidacao_params.merge(data_citacao: 'ontem'))
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejects abatimento sem valor' do
    liquidar(liquidacao_params.merge(abatimentos: [{ ano: 2023, mes: 2 }]))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('abatimento')
  end

  it 'rejects regime desconhecido' do
    liquidar(liquidacao_params.merge(regime_pos_ec136: 'ipca'))
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'returns 503 sem MOTOR_CALCULOS_URL' do
    liquidar
    expect(response).to have_http_status(:service_unavailable)
  end

  context 'when the motor responds' do
    before do
      stub_request(:post, "#{motor_url}/liquidacao")
        .to_return(status: 200, body: motor_body, headers: { 'Content-Type' => 'application/json' })
    end

    it 'proxies o payload com rmi string, regime default e abatimentos' do
      params = liquidacao_params.merge(
        no_piso: true,
        abatimentos: [{ ano: 2023, mes: 2, valor: '1300.5' }],
        honorarios_contratuais_pct: '30'
      )
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        liquidar(params)
      end
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['total_geral']).to eq('105000.00')
      matcher = have_requested(:post, "#{motor_url}/liquidacao").with do |req|
        body = JSON.parse(req.body)
        body['rmi'] == '1518.00' &&
          body['dib'] == '2022-03-10' &&
          body['data_citacao'] == '2023-05-02' &&
          body['no_piso'] == true &&
          body['regime_pos_ec136'] == 'art406' &&
          body['honorarios_contratuais_pct'] == '30' &&
          body['abatimentos'] == [{ 'ano' => 2023, 'mes' => 2, 'valor' => '1300.50' }] &&
          !body.key?('data_fim')
      end
      expect(WebMock).to matcher
    end

    it 'nao envia campos opcionais ausentes' do
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        liquidar({ rmi: '1518.00', dib: '2022-03-10' })
      end
      matcher = have_requested(:post, "#{motor_url}/liquidacao").with do |req|
        body = JSON.parse(req.body)
        !body.key?('data_citacao') && !body.key?('honorarios_contratuais_pct') && body['abatimentos'] == []
      end
      expect(WebMock).to matcher
    end
  end

  it 'repassa o detail 422 do motor' do
    stub_request(:post, "#{motor_url}/liquidacao")
      .to_return(status: 422, body: { detail: 'data_citacao anterior a dib' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    with_modified_env MOTOR_CALCULOS_URL: motor_url do
      liquidar
    end
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('data_citacao anterior a dib')
  end

  describe 'POST /liquidacao/pdf' do
    it 'devolve o PDF do motor como attachment com o cabecalho no payload' do
      stub_request(:post, "#{motor_url}/liquidacao/pdf")
        .to_return(status: 200, body: '%PDF-1.7 fake', headers: { 'Content-Type' => 'application/pdf' })
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        liquidar(liquidacao_params.merge(segurado_nome: 'Fulano de Tal', numero_processo: '123'),
                 admin.create_new_auth_token, 'liquidacao/pdf')
      end
      expect(response).to have_http_status(:success)
      expect(response.headers['Content-Type']).to include('application/pdf')
      expect(response.body).to start_with('%PDF')
      matcher = have_requested(:post, "#{motor_url}/liquidacao/pdf").with do |req|
        body = JSON.parse(req.body)
        body['segurado_nome'] == 'Fulano de Tal' && body['numero_processo'] == '123'
      end
      expect(WebMock).to matcher
    end

    it 'valida antes de chamar o motor' do
      liquidar({ dib: '2022-03-10' }, admin.create_new_auth_token, 'liquidacao/pdf')
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
