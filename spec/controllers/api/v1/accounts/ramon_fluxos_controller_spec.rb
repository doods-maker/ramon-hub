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
    expect(response.parsed_body['payload'].first).to include('nome' => 'Pós-contrato', 'gatilho_tipo' => 'manual', 'versao' => 1,
                                                             'ativo' => true, 'hoje' => 0)
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

  it 'fluxo do sistema é só leitura' do
    fluxo = fluxo_publicado(account, grafo, origem: 'sistema')
    patch "#{url}/#{fluxo.id}", params: { nome: 'Y' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
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

  it 'ADVBOX fora do ar devolve 503' do
    allow(Ramon::AdvboxClient).to receive(:settings).and_raise(Ramon::AdvboxClient::UnavailableError, 'AdvBox indisponível')
    get "#{url}/opcoes_advbox", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:service_unavailable)
  end
end
