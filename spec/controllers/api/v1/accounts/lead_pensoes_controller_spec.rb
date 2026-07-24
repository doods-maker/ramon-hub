require 'rails_helper'

RSpec.describe 'Lead Pensoes API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:lead) { create(:lead, account: account) }
  let(:dependente) { { tipo: 'conjuge', nascimento: '1980-01-01', invalido: false, inicio_uniao: '2010-05-01' } }
  let(:pensao_params) { { data_obito: '2026-01-15', dependentes: [dependente] } }
  let(:motor_response) do
    {
      'qualidade_falecido' => 'dispensada',
      'direito_adquirido' => true,
      'base' => { 'valor' => '2500.00', 'origem' => 'media' },
      'percentual' => 100,
      'rmi' => '2500.00',
      'quotas' => [{ 'tipo' => 'conjuge', 'quota_pct' => 100, 'cessa_em' => nil, 'fundamento' => 'quota unica', 'avisos' => [] }],
      'decisoes_pendentes' => [],
      'avisos' => []
    }
  end

  def calcular(params = pensao_params, headers = admin.create_new_auth_token)
    post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/pensao",
         params: params, headers: headers, as: :json
  end

  it 'returns unauthorized without auth' do
    calcular(pensao_params, {})
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns unauthorized for an agent of another account' do
    other_account = create(:account)
    other_admin = create(:user, account: other_account, role: :administrator)
    calcular(pensao_params, other_admin.create_new_auth_token)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects an invalid data_obito' do
    calcular(pensao_params.merge(data_obito: '15/01/2026'))
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejects a missing data_obito' do
    calcular(pensao_params.merge(data_obito: nil))
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejects missing dependentes' do
    calcular(pensao_params.merge(dependentes: []))
    expect(response).to have_http_status(:unprocessable_entity)
  end

  context 'when the motor responds' do
    before do
      allow(Ramon::MotorClient).to receive(:pensao).and_return(motor_response)
    end

    it 'proxies the segurado/competencias/vinculos from the stored CNIS and the dependentes cru' do
      lead.update!(cnis: {
                     'entrada' => {
                       'segurado' => { 'nascimento' => '1975-01-20', 'sexo' => 'F' },
                       'competencias' => [{ 'ano' => 2023, 'mes' => 5, 'salario' => '2500.00' }],
                       'vinculos' => [{ 'inicio' => '2005-01-01', 'fim' => '2020-12-31', 'tipo' => 'EMPREGO', 'indicadores' => [] }]
                     }
                   })
      calcular
      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to eq(motor_response)
      expect(Ramon::MotorClient).to have_received(:pensao).with(
        segurado: { 'nascimento' => '1975-01-20', 'sexo' => 'F' },
        data_obito: '2026-01-15',
        competencias: [{ 'ano' => 2023, 'mes' => 5, 'salario' => '2500.00' }],
        vinculos: [{ 'inicio' => '2005-01-01', 'fim' => '2020-12-31', 'tipo' => 'EMPREGO', 'indicadores' => [] }],
        dependentes: [{ 'tipo' => 'conjuge', 'nascimento' => '1980-01-01', 'invalido' => false, 'inicio_uniao' => '2010-05-01' }]
      )
    end

    it 'falls back to the contact nascimento/sexo when there is no CNIS' do
      contact = create(:contact, account: account, data_nascimento: '1980-05-10', sexo: 'M')
      lead.update!(contact: contact)
      calcular
      expect(response).to have_http_status(:success)
      expect(Ramon::MotorClient).to have_received(:pensao).with(
        hash_including(segurado: { nascimento: '1980-05-10', sexo: 'M' })
      )
    end

    it 'repassa valor_beneficio_obito e decisoes (com false explicito) pro motor' do
      calcular(pensao_params.merge(
                 valor_beneficio_obito: '1800.00',
                 decisoes: { desemprego: true, facultativo: nil, uniao_2_anos: false }
               ))
      expect(response).to have_http_status(:success)
      expect(Ramon::MotorClient).to have_received(:pensao).with(
        hash_including(
          valor_beneficio_obito: '1800.00',
          decisoes: { desemprego: true, uniao_2_anos: false }
        )
      )
    end

    it 'nao envia valor_beneficio_obito/decisoes quando ausentes' do
      payload_recebido = nil
      allow(Ramon::MotorClient).to receive(:pensao) do |payload|
        payload_recebido = payload
        motor_response
      end
      calcular
      expect(payload_recebido.keys).to match_array(%i[segurado data_obito competencias vinculos dependentes])
    end
  end

  it 'returns unprocessable entity when the motor rejects the input' do
    allow(Ramon::MotorClient).to receive(:pensao)
      .and_raise(Ramon::MotorClient::ValidationError, 'dependente sem tipo valido')
    calcular
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('dependente sem tipo valido')
  end

  it 'returns service unavailable when the motor is down' do
    allow(Ramon::MotorClient).to receive(:pensao)
      .and_raise(Ramon::MotorClient::UnavailableError, 'motor indisponível: connection refused')
    calcular
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body['error']).to include('motor indisponível')
  end
end
