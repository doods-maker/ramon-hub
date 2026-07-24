require 'rails_helper'

RSpec.describe 'Lead Maternidades API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:lead) { create(:lead, account: account) }
  let(:maternidade_params) { { data_evento: '2026-03-10', categoria: 'empregada' } }
  let(:motor_response) do
    {
      'rmi' => '2500.00',
      'memoria' => [],
      'carencia' => { 'exigida' => 0, 'fundamento' => 'empregada dispensa carencia' },
      'duracao_dias' => 120,
      'avisos' => []
    }
  end

  def calcular(params = maternidade_params, headers = admin.create_new_auth_token)
    post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/maternidade",
         params: params, headers: headers, as: :json
  end

  it 'returns unauthorized without auth' do
    calcular(maternidade_params, {})
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns unauthorized for an agent of another account' do
    other_account = create(:account)
    other_admin = create(:user, account: other_account, role: :administrator)
    calcular(maternidade_params, other_admin.create_new_auth_token)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects an invalid data_evento' do
    calcular(maternidade_params.merge(data_evento: '10/03/2026'))
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejects a missing data_evento' do
    calcular(maternidade_params.merge(data_evento: nil))
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejects categoria invalida' do
    calcular(maternidade_params.merge(categoria: 'autonoma'))
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejects categoria ausente' do
    calcular(maternidade_params.merge(categoria: nil))
    expect(response).to have_http_status(:unprocessable_entity)
  end

  context 'when the motor responds' do
    before do
      allow(Ramon::MotorClient).to receive(:maternidade).and_return(motor_response)
    end

    it 'proxies the segurado/competencias/vinculos from the stored CNIS' do
      lead.update!(cnis: {
                     'entrada' => {
                       'segurado' => { 'nascimento' => '1990-02-14', 'sexo' => 'F' },
                       'competencias' => [{ 'ano' => 2025, 'mes' => 12, 'salario' => '2200.00' }],
                       'vinculos' => [{ 'inicio' => '2020-01-01', 'fim' => nil, 'tipo' => 'EMPREGO', 'indicadores' => [] }]
                     }
                   })
      calcular
      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to eq(motor_response)
      expect(Ramon::MotorClient).to have_received(:maternidade).with(
        segurado: { 'nascimento' => '1990-02-14', 'sexo' => 'F' },
        data_evento: '2026-03-10',
        competencias: [{ 'ano' => 2025, 'mes' => 12, 'salario' => '2200.00' }],
        vinculos: [{ 'inicio' => '2020-01-01', 'fim' => nil, 'tipo' => 'EMPREGO', 'indicadores' => [] }],
        categoria: 'empregada'
      )
    end

    it 'falls back to the contact nascimento/sexo when there is no CNIS' do
      contact = create(:contact, account: account, data_nascimento: '1992-07-01', sexo: 'F')
      lead.update!(contact: contact)
      calcular
      expect(response).to have_http_status(:success)
      expect(Ramon::MotorClient).to have_received(:maternidade).with(
        hash_including(segurado: { nascimento: '1992-07-01', sexo: 'F' })
      )
    end
  end

  it 'returns unprocessable entity when the motor rejects the input' do
    allow(Ramon::MotorClient).to receive(:maternidade)
      .and_raise(Ramon::MotorClient::ValidationError, 'carencia nao cumprida')
    calcular
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('carencia nao cumprida')
  end

  it 'returns service unavailable when the motor is down' do
    allow(Ramon::MotorClient).to receive(:maternidade)
      .and_raise(Ramon::MotorClient::UnavailableError, 'motor indisponível: connection refused')
    calcular
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body['error']).to include('motor indisponível')
  end
end
