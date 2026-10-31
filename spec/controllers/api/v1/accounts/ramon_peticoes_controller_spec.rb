require 'rails_helper'

RSpec.describe 'Ramon Petições API', type: :request do
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:bia) { create(:user, account: account, role: :agent) }
  let(:fora) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_peticoes" }
  let(:pdf) { Rails.root.join('spec/assets/sample.pdf') }

  before do
    time = create(:team, account: account, name: Ramon::Papeis::JURIDICO)
    [ana, bia].each { |u| create(:team_member, team: time, user: u) }
  end

  # CNJ válido com J=4 TR=04 (mesma fórmula do peticao_spec)
  def numero_valido_trf4
    dd = format('%02d', 98 - ('50012342026404720700'.to_i % 97))
    "5001234-#{dd}.2026.4.04.7207"
  end

  def criar(user = ana, **params)
    post url, params: { numero_processo: numero_valido_trf4.delete('^0-9') }.merge(params), headers: user.create_new_auth_token, as: :json
  end

  def peticao_com_principal
    account.peticoes.create!(criado_por: ana, responsavel: ana, numero_processo: numero_valido_trf4).tap do |p|
      p.arquivos.create!(nome: 'Peticao.pdf', tipo: 'peticao', posicao: 1, principal: true, origem: 'upload', tamanho: 10)
    end
  end

  def enviar(peticao, user = ana, **params)
    post "#{url}/#{peticao.id}/arquivos", params: { file: fixture_file_upload(pdf, 'application/pdf') }.merge(params),
                                          headers: user.create_new_auth_token
  end

  it 'agente fora do jurídico recebe 401 em index e drive' do
    get url, headers: fora.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    get "#{url}/drive", headers: fora.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'membro do juridico cria com número sem máscara e recebe tribunal trf4' do
    criar
    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('tribunal' => 'trf4', 'numero_processo' => numero_valido_trf4, 'status' => 'rascunho')
    expect(response.parsed_body['responsavel']).to include('id' => ana.id)
    expect(account.peticoes.sole.criado_por).to eq(ana)
  end

  it 'create com número inválido → 422' do
    criar(ana, numero_processo: '5001234-00.2026.4.04.7207')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['errors']).to be_present
  end

  it 'index lista rascunhos por prazo antes das protocoladas, com tribunais e tipos' do
    sem_prazo = peticao_com_principal
    com_prazo = peticao_com_principal.tap { |p| p.update!(prazo: Date.new(2026, 11, 3)) }
    feita = peticao_com_principal.tap { |p| p.update!(status: 'protocolada', protocolada_em: Time.current) }
    get url, headers: ana.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].pluck('id')).to eq([com_prazo.id, sem_prazo.id, feita.id])
    expect(response.parsed_body['tribunais'].pluck('chave')).to include('trf4')
    expect(response.parsed_body['tipos']).to include('peticao')

    get url, params: { status: 'protocolada' }, headers: ana.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].pluck('id')).to eq([feita.id])
  end

  it 'upload de PDF entra no pacote; problemas some quando há principal' do
    criar
    peticao = account.peticoes.sole
    enviar(peticao, ana, principal: 'true', tipo: 'peticao')
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['arquivos'].size).to eq(1)
    expect(response.parsed_body['arquivos'].first).to include('origem' => 'upload', 'principal' => true, 'posicao' => 1)
    expect(response.parsed_body['problemas']).to eq([])
  end

  it 'upload de formato inválido → 422 formato' do
    criar
    audio = fixture_file_upload(Rails.root.join('spec/assets/sample.mp3'), 'audio/mpeg')
    post "#{url}/#{account.peticoes.sole.id}/arquivos", params: { file: audio }, headers: ana.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('error' => 'formato')
  end

  it 'arquivos_drive baixa pelo DriveClient (stub) e grava origem drive' do
    criar
    allow(Ramon::DriveClient).to receive(:download).with('drv1').and_return([File.binread(pdf), 'application/pdf', 'Laudo medico.pdf'])
    post "#{url}/#{account.peticoes.sole.id}/arquivos_drive", params: { file_ids: ['drv1'] }, headers: ana.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['arquivos'].first).to include('origem' => 'drive', 'tipo' => 'laudo_medico')
    expect(PeticaoArquivo.sole.drive_origem_id).to eq('drv1')
  end

  it 'troca principal, reordena e remove renumerando' do
    peticao = peticao_com_principal
    outro = peticao.arquivos.create!(nome: 'Rg.pdf', tipo: 'documento_identificacao', posicao: 2, origem: 'upload', tamanho: 5)
    primeiro = peticao.arquivos.first

    patch "#{url}/#{peticao.id}/arquivos/#{outro.id}", params: { principal: true }, headers: ana.create_new_auth_token, as: :json
    expect(peticao.arquivos.reload.pluck(:id, :principal)).to contain_exactly([primeiro.id, false], [outro.id, true])

    patch "#{url}/#{peticao.id}/ordem", params: { ids: [outro.id, primeiro.id] }, headers: ana.create_new_auth_token, as: :json
    expect(response.parsed_body['arquivos'].pluck('id')).to eq([outro.id, primeiro.id])

    delete "#{url}/#{peticao.id}/arquivos/#{outro.id}", headers: ana.create_new_auth_token, as: :json
    expect(response.parsed_body['arquivos'].pluck('id', 'posicao')).to eq([[primeiro.id, 1]])
  end

  it 'registrar_protocolo: outro membro do jurídico → 401; responsável → 200 e status protocolada' do
    peticao = peticao_com_principal
    path = "#{url}/#{peticao.id}/registrar_protocolo"

    post path, params: { numero_evento: '15' }, headers: bia.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to include('error' => 'SO_RESPONSAVEL')

    expect do
      post path, params: { numero_evento: '15', comprovante: fixture_file_upload(pdf, 'application/pdf') }, headers: ana.create_new_auth_token
    end.to have_enqueued_job(Ramon::PeticaoArquivarJob).with(peticao.id)
    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('status' => 'protocolada', 'numero_evento' => '15')
  end

  it 'registrar_protocolo com pacote incompleto → 422' do
    criar
    post "#{url}/#{account.peticoes.sole.id}/registrar_protocolo", params: { numero_evento: '1' }, headers: ana.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['errors']).to be_present
  end

  it 'depois de protocolada: POST arquivos, DELETE petição e PATCH ordem → 422' do
    peticao = peticao_com_principal.tap { |p| p.update!(status: 'protocolada') }

    enviar(peticao)
    expect(response).to have_http_status(:unprocessable_entity)
    delete "#{url}/#{peticao.id}", headers: ana.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    patch "#{url}/#{peticao.id}/ordem", params: { ids: [peticao.arquivos.first.id] }, headers: ana.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Peticao.exists?(peticao.id)).to be(true)
  end

  it 'drive sem configuração → 503 DRIVE_OFF' do
    allow(Ramon::DriveClient).to receive(:configured?).and_return(false)
    get "#{url}/drive", headers: ana.create_new_auth_token, as: :json
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to include('error' => 'DRIVE_OFF')
    get "#{url}/drive_busca", params: { q: 'laudo' }, headers: ana.create_new_auth_token, as: :json
    expect(response).to have_http_status(:service_unavailable)
  end

  it 'drive navega: raiz sem pai; subpasta com pai; busca' do
    allow(Ramon::DriveClient).to receive_messages(configured?: true, root_id: 'raiz', children: [{ id: 'a' }], parent_of: 'raiz',
                                                  search: [{ id: 'b' }])
    get "#{url}/drive", headers: ana.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('pasta_id' => 'raiz', 'pai_id' => nil, 'raiz_id' => 'raiz', 'itens' => [{ 'id' => 'a' }])
    get "#{url}/drive", params: { pasta_id: 'sub' }, headers: ana.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('pasta_id' => 'sub', 'pai_id' => 'raiz')
    get "#{url}/drive_busca", params: { q: 'laudo' }, headers: ana.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('itens' => [{ 'id' => 'b' }])
  end

  it 'processos vêm do portal do cliente pelo CPF do contato; sem portal → []' do
    contato = create(:contact, account: account, cpf: '12345678901')
    get "#{url}/processos", params: { contact_id: contato.id }, headers: ana.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('processos' => [])

    create(:portal_cliente, account: account, cpf: '12345678901', processos: [{ 'id' => 1, 'numero' => '5001234-00', 'tipo' => 'Previdenciário' }])
    get "#{url}/processos", params: { contact_id: contato.id }, headers: ana.create_new_auth_token, as: :json
    expect(response.parsed_body['processos']).to eq([{ 'numero' => '5001234-00', 'tipo' => 'Previdenciário' }])
  end
end
