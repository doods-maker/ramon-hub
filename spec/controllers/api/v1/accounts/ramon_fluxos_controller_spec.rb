require 'rails_helper'

RSpec.describe 'Ramon Fluxos API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_fluxos" }
  let(:grafo) { grafo_linear({ 'tipo' => 'manual' }, ['nota_privada', { 'texto' => 'oi' }]) }

  it 'agente não acessa' do
    get url, headers: agente.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'cria, edita o rascunho, publica e lista com contadores' do
    post url, params: { nome: 'Pós-contrato', rascunho: grafo }, headers: admin.create_new_auth_token, as: :json
    id = response.parsed_body['id']
    patch "#{url}/#{id}", params: { ativo: true, limite_dia: 20 }, headers: admin.create_new_auth_token, as: :json
    post "#{url}/#{id}/publicar", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('versao' => 1)

    get url, headers: admin.create_new_auth_token, as: :json
    meu = response.parsed_body['payload'].find { |f| f['origem'] == 'usuario' }
    expect(meu).to include('nome' => 'Pós-contrato', 'gatilho_tipo' => 'manual', 'versao' => 1, 'ativo' => true, 'hoje' => 0)
    expect(response.parsed_body['resumo']).to include('ligados' => 1, 'total' => 1)
  end

  it 'publicar inválido devolve os erros' do
    post url, params: { nome: 'X', rascunho: { nos: [], setas: [] } }, headers: admin.create_new_auth_token, as: :json
    post "#{url}/#{response.parsed_body['id']}/publicar", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['erros']).to include('O fluxo precisa de exatamente 1 gatilho')
  end

  it 'ensaio com um lead devolve a trilha' do
    fluxo = fluxo_publicado(account, grafo)
    lead = create(:lead, account: account)
    post "#{url}/#{fluxo.id}/ensaio", params: { lead_id: lead.id, usar: 'publicada' }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('status' => 'concluida', 'ensaio' => true)
    expect(response.parsed_body['trilha'].pluck('no')).to eq(%w[g p1])
  end

  it 'ensaio da publicada sem publicar devolve 422' do
    post url, params: { nome: 'Z', rascunho: grafo }, headers: admin.create_new_auth_token, as: :json
    post "#{url}/#{response.parsed_body['id']}/ensaio", params: { lead_id: create(:lead, account: account).id, usar: 'publicada' },
                                                        headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['erros']).to eq(['O fluxo ainda não foi publicado'])
  end

  it 'fluxo do sistema é só leitura: não edita, não publica, não roda e não ensaia' do
    fluxo = fluxo_publicado(account, grafo, origem: 'sistema')
    lead = create(:lead, account: account)
    patch "#{url}/#{fluxo.id}", params: { nome: 'Y' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    post "#{url}/#{fluxo.id}/publicar", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    post "#{url}/#{fluxo.id}/ensaio", params: { lead_id: lead.id }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    post "#{url}/#{fluxo.id}/rodar", params: { lead_id: lead.id }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(fluxo.execucoes.count).to eq(0)
  end

  it 'a lista traz os 29 do sistema com Hoje, grupo e selo; os 4 números contam só os meus' do
    fluxo_publicado(account, grafo)
    get url, headers: admin.create_new_auth_token, as: :json
    sistema = response.parsed_body['payload'].select { |f| f['origem'] == 'sistema' }
    expect(sistema.size).to eq(29)
    avisos = sistema.find { |f| f['sistema_chave'] == 'avisos_painel' }
    expect(avisos).to include('hoje' => nil, 'ativo' => false, 'versao' => nil, 'grupo' => 'painel_cliente',
                              'alcance' => 'fala_com_cliente', 'gatilho_rotulo' => 'Todo dia às 08:00 (só com PORTAL_AVISOS=on)')
    expect(sistema.find { |f| f['sistema_chave'] == 'lead_ganho' }).to include('hoje' => 0, 'alcance' => nil)
    expect(response.parsed_body['resumo']).to include('ligados' => 1, 'total' => 1)

    get "#{url}/#{avisos['id']}", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('alcance' => 'fala_com_cliente', 'origem' => 'sistema')
    expect(response.parsed_body['rascunho']['nos']).to be_present
  end

  it 'lista execuções do fluxo' do
    fluxo = fluxo_publicado(account, grafo)
    Ramon::Fluxos::Disparo.manual(fluxo, create(:lead, account: account))
    get "#{url}/#{fluxo.id}/execucoes", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].size).to eq(1)
  end

  it 'uma execução devolve o desenho em que rodou' do
    fluxo = fluxo_publicado(account, grafo)
    execucao = Ramon::Fluxos::Disparo.ensaiar(fluxo, create(:lead, account: account), usar: 'publicada')
    fluxo.update!(rascunho: { nos: [], setas: [] }) # editar depois não muda o desenho da execução
    get "#{url}/#{fluxo.id}/execucoes/#{execucao.id}", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['grafo']['nos'].pluck('id')).to eq(%w[g p1])
  end

  it 'opções do ADVBOX para o passo (só admin, sem e-mail)' do
    allow(Ramon::AdvboxClient).to receive(:settings).and_return(
      'users' => [{ 'id' => 266_778, 'name' => 'EDUARDO SCHLATA', 'email' => 'nao-sai' }],
      'tasks' => [{ 'id' => 8_745_408, 'task' => 'AGUARDANDO DOCUMENTOS CLIENTE', 'reward' => 5 }]
    )
    get "#{url}/opcoes_advbox", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to eq('usuarios' => [{ 'id' => 266_778, 'nome' => 'EDUARDO SCHLATA' }],
                                       'tipos_tarefa' => [{ 'id' => 8_745_408, 'nome' => 'AGUARDANDO DOCUMENTOS CLIENTE' }])
    get "#{url}/opcoes_advbox", headers: agente.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'ADVBOX fora do ar ou recusando (4xx) devolve 503' do
    [Ramon::AdvboxClient::UnavailableError.new('AdvBox indisponível'), Ramon::AdvboxClient::RequestError.new(401, {})].each do |erro|
      allow(Ramon::AdvboxClient).to receive(:settings).and_raise(erro)
      get "#{url}/opcoes_advbox", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to eq('erro' => erro.message)
    end
  end
end
