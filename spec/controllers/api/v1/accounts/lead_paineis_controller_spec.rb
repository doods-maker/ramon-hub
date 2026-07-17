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
    # forma real: entrada.vinculos NÃO tem seq (só quem tem é cnis['vinculos'],
    # o vinculos_detalhe) — mesma fixture do lead_cnis_controller_spec.rb.
    # A fusão é por posição: 1º de entrada.vinculos <-> 1º de cnis['vinculos'].
    let(:cnis_com_dois_vinculos) do
      {
        'entrada' => {
          'segurado' => { 'nascimento' => '1975-01-20', 'sexo' => 'F' },
          'competencias' => [],
          'vinculos' => [
            { 'inicio' => '2005-01-01', 'fim' => '2009-12-31', 'tipo' => 'EMPREGO', 'indicadores' => [] },
            { 'inicio' => '2010-01-01', 'fim' => '2015-12-31', 'tipo' => 'EMPREGO', 'indicadores' => [] }
          ]
        },
        'vinculos' => [
          { 'seq' => 1, 'tipo' => 'EMPREGO', 'origem' => 'OUTRA LTDA' },
          { 'seq' => 3, 'tipo' => 'EMPREGO', 'origem' => 'ACME LTDA' }
        ]
      }
    end

    it 'funde especiais nos vinculos por posicao (via cnis[vinculos]/vinculos_detalhe) e persiste nos parametros' do
      lead.update!(cnis: cnis_com_dois_vinculos)
      corpo_enviado = nil
      stub_request(:post, "#{motor_url}/painel").with { |req| corpo_enviado = JSON.parse(req.body); true }
        .to_return(status: 200, body: { resumo: {}, cartoes: [], avisos: [] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        calcular(painel_params.merge(vinculos_extras: [], especiais: { '3' => { 'grau' => 25 } }.to_json))
      end

      expect(response).to have_http_status(:success)
      # seq 3 é o 2º de cnis['vinculos'] -> deve cair no 2º de entrada.vinculos
      alvo = corpo_enviado['vinculos'].find { |v| v['inicio'] == '2010-01-01' }
      outro = corpo_enviado['vinculos'].find { |v| v['inicio'] == '2005-01-01' }
      expect(alvo['especial']).to eq('grau' => 25, 'inicio' => nil, 'fim' => nil)
      expect(outro['especial']).to be_nil
      expect(lead.reload.cnis.dig('parametros', 'especiais')).to be_present
    end

    it 'remove a marcacao persistida quando reaplica com especiais vazio (desmarcou tudo)' do
      lead.update!(cnis: cnis_com_dois_vinculos.merge('parametros' => { 'especiais' => { '3' => { 'grau' => 25 } }.to_json }))
      stub_request(:post, "#{motor_url}/painel")
        .to_return(status: 200, body: { resumo: {}, cartoes: [], avisos: [] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        calcular(painel_params.merge(vinculos_extras: [], especiais: ''))
      end

      expect(response).to have_http_status(:success)
      expect(lead.reload.cnis.dig('parametros', 'especiais')).to be_nil
    end

    it 'pula a fusao (sem 500) quando entrada.vinculos e cnis[vinculos] tem tamanhos diferentes' do
      cnis = cnis_com_dois_vinculos
      cnis['vinculos'] = [cnis['vinculos'].first] # dado velho/corrompido: só 1 detalhe pra 2 vinculos
      lead.update!(cnis: cnis)
      corpo_enviado = nil
      stub_request(:post, "#{motor_url}/painel").with { |req| corpo_enviado = JSON.parse(req.body); true }
        .to_return(status: 200, body: { resumo: {}, cartoes: [], avisos: [] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        calcular(painel_params.merge(vinculos_extras: [], especiais: { '3' => { 'grau' => 25 } }.to_json))
      end

      expect(response).to have_http_status(:success)
      expect(corpo_enviado['vinculos'].length).to eq(2)
      expect(corpo_enviado['vinculos'].none? { |v| v['especial'] }).to be true
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

    # JSON válido mas de forma errada (não é um mapa seq => {grau,...}) —
    # sem a checagem de forma isso passava e explodia depois com TypeError/
    # NoMethodError no merge/motor.
    ['[]', '123', '{"3":"x"}'].each do |especiais_malformado|
      it "especiais com forma invalida (#{especiais_malformado}) devolve 422 sem chamar o motor" do
        with_modified_env MOTOR_CALCULOS_URL: motor_url do
          calcular(painel_params.merge(especiais: especiais_malformado))
        end
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to be_present
        expect(WebMock).not_to have_requested(:post, "#{motor_url}/painel")
      end
    end
  end

  context 'persistencia de especiais sem CNIS anexado' do
    it 'nao cria lead.cnis do zero so pra guardar parametros de especiais' do
      stub_request(:post, "#{motor_url}/painel")
        .to_return(status: 200, body: motor_body, headers: { 'Content-Type' => 'application/json' })

      expect(lead.cnis).to be_blank
      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        calcular(painel_params.merge(especiais: { '3' => { 'grau' => 25 } }.to_json))
      end

      expect(response).to have_http_status(:success)
      expect(lead.reload.cnis).to be_blank
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
