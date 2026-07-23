require 'rails_helper'

RSpec.describe 'Lead Elegibilidades API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:lead) { create(:lead, account: account) }
  let(:motor_url) { 'http://motor:8000' }
  let(:elegibilidade_params) { { der: '2026-06-30' } }
  let(:motor_response) do
    {
      'data_referencia' => '2026-06-30',
      'qualidade' => { 'cenarios' => { 'unico' => { 'mantida' => true, 'ate' => nil, 'fundamento' => 'em atividade' } } },
      'carencia' => { 'total' => 180, 'perda_qualidade_anterior' => false, 'desde_nova_filiacao' => false, 'art_27a' => nil },
      'lacunas' => [],
      'decisoes_pendentes' => [],
      'avisos' => []
    }
  end

  def analisar(params = elegibilidade_params, headers = admin.create_new_auth_token)
    post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/elegibilidade",
         params: params, headers: headers, as: :json
  end

  it 'returns unauthorized without auth' do
    analisar(elegibilidade_params, {})
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns unauthorized for an agent of another account' do
    other_account = create(:account)
    other_admin = create(:user, account: other_account, role: :administrator)
    analisar(elegibilidade_params, other_admin.create_new_auth_token)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects an invalid der' do
    analisar(elegibilidade_params.merge(der: '30/06/2026'))
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejects a missing der' do
    analisar(elegibilidade_params.merge(der: nil))
    expect(response).to have_http_status(:unprocessable_entity)
  end

  context 'when the motor responds' do
    before do
      allow(Ramon::MotorClient).to receive(:elegibilidade).and_return(motor_response)
    end

    it 'proxies the segurado/competencias/vinculos from the stored CNIS' do
      lead.update!(cnis: {
                     'entrada' => {
                       'segurado' => { 'nascimento' => '1975-01-20', 'sexo' => 'F' },
                       'competencias' => [{ 'ano' => 2023, 'mes' => 5, 'salario' => '2500.00' }],
                       'vinculos' => [{ 'inicio' => '2005-01-01', 'fim' => '2020-12-31', 'tipo' => 'EMPREGO', 'indicadores' => [] }]
                     }
                   })
      analisar
      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to eq(motor_response)
      expect(Ramon::MotorClient).to have_received(:elegibilidade).with(
        segurado: { 'nascimento' => '1975-01-20', 'sexo' => 'F' },
        der: '2026-06-30',
        competencias: [{ 'ano' => 2023, 'mes' => 5, 'salario' => '2500.00' }],
        vinculos: [{ 'inicio' => '2005-01-01', 'fim' => '2020-12-31', 'tipo' => 'EMPREGO', 'indicadores' => [] }]
      )
    end

    it 'falls back to the contact nascimento/sexo when there is no CNIS' do
      contact = create(:contact, account: account, data_nascimento: '1980-05-10', sexo: 'M')
      lead.update!(contact: contact)
      analisar
      expect(response).to have_http_status(:success)
      expect(Ramon::MotorClient).to have_received(:elegibilidade).with(
        hash_including(segurado: { nascimento: '1980-05-10', sexo: 'M' })
      )
    end

    it 'repassa data_referencia, decisoes e simular_lacunas pro motor' do
      analisar(elegibilidade_params.merge(
                 data_referencia: '2026-07-01',
                 decisoes: { desemprego: true, facultativo: nil },
                 simular_lacunas: true
               ))
      expect(response).to have_http_status(:success)
      expect(Ramon::MotorClient).to have_received(:elegibilidade).with(
        hash_including(
          data_referencia: '2026-07-01',
          decisoes: { desemprego: true },
          simular_lacunas: true
        )
      )
    end

    it 'nao envia decisoes/simular_lacunas/data_referencia quando ausentes' do
      payload_recebido = nil
      allow(Ramon::MotorClient).to receive(:elegibilidade) do |payload|
        payload_recebido = payload
        motor_response
      end
      analisar
      expect(payload_recebido.keys).to match_array(%i[segurado der competencias vinculos])
    end
  end

  it 'returns unprocessable entity when the motor rejects the input' do
    allow(Ramon::MotorClient).to receive(:elegibilidade)
      .and_raise(Ramon::MotorClient::ValidationError, 'DER anterior à perda de qualidade')
    analisar
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('DER anterior à perda de qualidade')
  end

  it 'returns service unavailable when the motor is down' do
    allow(Ramon::MotorClient).to receive(:elegibilidade)
      .and_raise(Ramon::MotorClient::UnavailableError, 'motor indisponível: connection refused')
    analisar
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body['error']).to include('motor indisponível')
  end
end
