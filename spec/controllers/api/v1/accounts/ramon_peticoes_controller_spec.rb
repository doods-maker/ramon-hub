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

  it 'membro do time advogados cria com número sem máscara e recebe tribunal trf4' do
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
    allow(Ramon::DriveClient).to receive(:configured?).and_return(true)
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

  it 'registrar_protocolo sem comprovante (ou comprovante vazio) → 422, não 500' do
    peticao = peticao_com_principal
    path = "#{url}/#{peticao.id}/registrar_protocolo"
    [{ numero_evento: '15' }, { numero_evento: '15', comprovante: '' }].each do |params|
      post path, params: params, headers: ana.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors'].join).to include('comprovante')
    end
    expect(peticao.reload.status).to eq('rascunho')
  end

  it 'baixar devolve o PDF com o nome numerado; outro pacote → 404' do
    criar
    peticao = account.peticoes.sole
    enviar(peticao, ana, tipo: 'peticao')
    arquivo = response.parsed_body['arquivos'].first
    expect(arquivo['url']).to eq("/api/v1/accounts/#{account.id}/ramon_peticoes/#{peticao.id}/arquivos/#{arquivo['id']}/baixar")

    get arquivo['url'], headers: ana.create_new_auth_token
    expect(response).to have_http_status(:success)
    expect(response.headers['Content-Type']).to start_with('application/pdf')
    expect(response.headers['Content-Disposition']).to include('attachment', '01 sample.pdf')
    expect(response.body).to start_with('%PDF')

    outra = peticao_com_principal
    get "#{url}/#{outra.id}/arquivos/#{arquivo['id']}/baixar", headers: ana.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    get arquivo['url'], headers: fora.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'trocar o cliente no update recalcula a pasta-base do seletor do Drive' do
    contato = create(:contact, account: account)
    create(:lead, account: account, contact: contato, custom_attributes: { 'drive' => { 'pasta_id' => 'pasta-cliente' } })
      .update_column(:won_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
    criar
    peticao = account.peticoes.sole
    allow(Ramon::DriveClient).to receive(:configured?).and_return(false)
    expect(response.parsed_body['drive_pasta_base_id']).to be_nil

    patch "#{url}/#{peticao.id}", params: { contact_id: contato.id }, headers: ana.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('drive_pasta_base_id' => 'pasta-cliente', 'drive_ligado' => false)
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
    criar
    post "#{url}/#{account.peticoes.sole.id}/arquivos_drive", params: { file_ids: ['drv1'] }, headers: ana.create_new_auth_token, as: :json
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to include('error' => 'DRIVE_OFF')
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
    contato = create(:contact, account: account, cpf: '52998224725')
    get "#{url}/processos", params: { contact_id: contato.id }, headers: ana.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('processos' => [])

    create(:portal_cliente, account: account, cpf: '52998224725', processos: [{ 'id' => 1, 'numero' => '5001234-00', 'tipo' => 'Previdenciário' }])
    get "#{url}/processos", params: { contact_id: contato.id }, headers: ana.create_new_auth_token, as: :json
    expect(response.parsed_body['processos']).to eq([{ 'numero' => '5001234-00', 'tipo' => 'Previdenciário' }])
  end

  describe 'pela pasta' do
    let(:headers) { ana.create_new_auth_token }

    before { allow(Ramon::DriveClient).to receive_messages(configured?: true, pasta?: true) }

    def da_pasta(pasta_id: 'p1', **attrs)
      account.peticoes.create!({ criado_por: ana, responsavel: ana, status: 'conferencia', pela_pasta: true, drive_pasta_id: pasta_id,
                                 leitura: { 'estado' => 'ok', 'campos' => { 'cpf' => '52998224725' } } }.merge(attrs)).tap do |p|
        p.arquivos.create!(nome: 'Peticao.pdf', tipo: 'peticao', posicao: 1, principal: true, origem: 'drive', tamanho: 10)
      end
    end

    it 'apontar cria a petição em conferência e enfileira a leitura, com responsável padrão em quem apontou' do
      expect { post "#{url}/pela_pasta", params: { pasta_id: 'p1' }, headers: headers, as: :json }
        .to have_enqueued_job(Ramon::PeticaoLerPastaJob)
      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('status' => 'conferencia', 'pela_pasta' => true, 'drive_pasta_id' => 'p1',
                                              'alertas' => [], 'avisos' => [])
      expect(response.parsed_body['leitura']).to include('estado' => 'lendo')
      expect(response.parsed_body['leitura']['lendo_desde']).to be_present
      expect(response.parsed_body['responsavel']).to include('id' => ana.id)
      expect(account.peticoes.sole.criado_por).to eq(ana)
    end

    it 'pasta_id em branco → 422' do
      post "#{url}/pela_pasta", params: { pasta_id: ' ' }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.peticoes.count).to eq(0)
    end

    it 'apontar a mesma pasta de novo devolve 422 com a petição existente' do
      existente = da_pasta
      expect { post "#{url}/pela_pasta", params: { pasta_id: 'p1' }, headers: headers, as: :json }
        .not_to have_enqueued_job(Ramon::PeticaoLerPastaJob)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'pasta_ja_usada', 'peticao_id' => existente.id)
    end

    it 'pasta_ja_usada também quando a corrida estoura a unicidade na hora de gravar' do
      existente = da_pasta
      # a checagem prévia não enxerga a petição (corrida); a gravação estoura a unicidade
      allow_any_instance_of(Api::V1::Accounts::RamonPeticoesController) # rubocop:disable RSpec/AnyInstance
        .to receive(:peticao_da_pasta).and_return(nil, existente)
      post "#{url}/pela_pasta", params: { pasta_id: 'p1' }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'pasta_ja_usada', 'peticao_id' => existente.id)
    end

    it 'pasta inválida (aspas, não é pasta, id inexistente) → 422 pasta_invalida, sem criar nem enfileirar', :aggregate_failures do
      allow(Ramon::DriveClient).to receive(:pasta?).with('arquivo1').and_return(false)
      allow(Ramon::DriveClient).to receive(:pasta?).with('nao-existe').and_return(false)
      ["x' or '1'='1", 'arquivo1', 'nao-existe'].each do |id|
        expect { post "#{url}/pela_pasta", params: { pasta_id: id }, headers: headers, as: :json }
          .not_to have_enqueued_job(Ramon::PeticaoLerPastaJob)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to include('error' => 'pasta_invalida')
      end
      expect(account.peticoes.count).to eq(0)
      expect(Ramon::DriveClient).not_to have_received(:pasta?).with("x' or '1'='1")
    end

    it 'apontar sem Drive configurado → 503' do
      allow(Ramon::DriveClient).to receive(:configured?).and_return(false)
      post "#{url}/pela_pasta", params: { pasta_id: 'p1' }, headers: headers, as: :json
      expect(response).to have_http_status(:service_unavailable)
      expect(account.peticoes.count).to eq(0)
    end

    it 'protocolada depois de carregada (corrida com a trava): 422 protocolada, sem mudar status nem enfileirar' do
      peticao = da_pasta.tap { |p| p.update!(status: 'protocolada', numero_processo: numero_valido_trf4) }
      allow_any_instance_of(Peticao).to receive(:editavel?).and_return(true) # rubocop:disable RSpec/AnyInstance
      expect { post "#{url}/#{peticao.id}/reler_pasta", headers: headers, as: :json }
        .not_to have_enqueued_job(Ramon::PeticaoLerPastaJob)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'protocolada')
      expect(peticao.reload.status).to eq('protocolada')
    end

    it 'agente fora do jurídico recebe 401 em pela_pasta, reler_pasta e confirmar' do
      peticao = da_pasta
      outro = fora.create_new_auth_token
      post "#{url}/pela_pasta", params: { pasta_id: 'p2' }, headers: outro, as: :json
      expect(response).to have_http_status(:unauthorized)
      post "#{url}/#{peticao.id}/reler_pasta", headers: outro, as: :json
      expect(response).to have_http_status(:unauthorized)
      post "#{url}/#{peticao.id}/confirmar", headers: outro, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(account.peticoes.count).to eq(1)
    end

    it 'pacote de pasta só muda tipo e principal: arquivos, arquivos_drive, remover_arquivo e ordem dão 42', :aggregate_failures do
      peticao = da_pasta
      arquivo = peticao.arquivos.first
      enviar(peticao)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'pacote_da_pasta')
      post "#{url}/#{peticao.id}/arquivos_drive", params: { file_ids: ['x'] }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'pacote_da_pasta')
      delete "#{url}/#{peticao.id}/arquivos/#{arquivo.id}", headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      patch "#{url}/#{peticao.id}/ordem", params: { ids: [arquivo.id] }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(peticao.arquivos.reload.pluck(:id)).to eq([arquivo.id])

      patch "#{url}/#{peticao.id}/arquivos/#{arquivo.id}", params: { tipo: 'laudo_medico' }, headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(arquivo.reload.tipo).to eq('laudo_medico')
    end

    it 'reler em andamento dá 409; lendo há mais de 10 min pode reler, mantendo os campo', :aggregate_failures do
      peticao = da_pasta(leitura: { 'estado' => 'lendo', 'lendo_desde' => 2.minutes.ago.iso8601, 'campos' => { 'cpf' => '1' } })
      expect { post "#{url}/#{peticao.id}/reler_pasta", headers: headers, as: :json }
        .not_to have_enqueued_job(Ramon::PeticaoLerPastaJob)
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to include('error' => 'em_leitura')

      peticao.update!(leitura: peticao.leitura.merge('lendo_desde' => 11.minutes.ago.iso8601))
      expect { post "#{url}/#{peticao.id}/reler_pasta", headers: headers, as: :json }
        .to have_enqueued_job(Ramon::PeticaoLerPastaJob).with(peticao.id)
      expect(response).to have_http_status(:success)
      leitura = peticao.reload.leitura
      expect(leitura).to include('estado' => 'lendo', 'campos' => { 'cpf' => '1' })
      expect(Time.zone.parse(leitura['lendo_desde'])).to be > 1.minute.ago
    end

    it 'reler um rascunho da pasta volta o status a conferência' do
      peticao = da_pasta(status: 'rascunho', numero_processo: numero_valido_trf4)
      post "#{url}/#{peticao.id}/reler_pasta", headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(peticao.reload.status).to eq('conferencia')
      expect(peticao.leitura['estado']).to eq('lendo')
    end

    it 'reler protocolada é recusado; petição que não é da pasta dá 422 nao_e_pela_pasta' do
      protocolada = da_pasta.tap { |p| p.update!(status: 'protocolada', numero_processo: numero_valido_trf4) }
      expect { post "#{url}/#{protocolada.id}/reler_pasta", headers: headers, as: :json }
        .not_to have_enqueued_job(Ramon::PeticaoLerPastaJob)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'protocolada')
      expect(protocolada.reload.status).to eq('protocolada')

      comum = peticao_com_principal
      post "#{url}/#{comum.id}/reler_pasta", headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'nao_e_pela_pasta')
      expect(comum.reload.status).to eq('rascunho')
    end

    it 'reler sem Drive configurado → 503' do
      peticao = da_pasta
      allow(Ramon::DriveClient).to receive(:configured?).and_return(false)
      post "#{url}/#{peticao.id}/reler_pasta", headers: headers, as: :json
      expect(response).to have_http_status(:service_unavailable)
    end

    it 'confirmar sem alertas_confirmados com alerta dá 422 e com confirmação vira rascunho', :aggregate_failures do
      peticao = da_pasta(numero_processo: numero_valido_trf4,
                         leitura: { 'estado' => 'ok', 'cpf_pasta' => '111.111.111-11', 'campos' => { 'cpf' => '52998224725' } })
      post "#{url}/#{peticao.id}/confirmar", headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors']).to be_present
      expect(peticao.reload.status).to eq('conferencia')

      get "#{url}/#{peticao.id}", headers: headers, as: :json
      expect(response.parsed_body['alertas']).to eq(['cpf_diferente'])

      post "#{url}/#{peticao.id}/confirmar", params: { confirmar_alertas: 'true' }, headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('status' => 'rascunho')
      expect(response.parsed_body).not_to have_key('alertas')
      expect(peticao.reload.status).to eq('rascunho')
    end

    it 'confirmar sem alertas vira rascunho; leitura em andamento dá 422' do
      lendo = da_pasta(pasta_id: 'p9', numero_processo: numero_valido_trf4, leitura: { 'estado' => 'lendo' })
      post "#{url}/#{lendo.id}/confirmar", headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      limpa = da_pasta(numero_processo: numero_valido_trf4)
      post "#{url}/#{limpa.id}/confirmar", headers: headers, as: :json
      expect(response).to have_http_status(:success)
      expect(limpa.reload.status).to eq('rascunho')
    end

    it 'index põe a conferência primeiro, a mais antiga antes, e não calcula alertas' do
      rascunho = peticao_com_principal
      nova = da_pasta(pasta_id: 'n').tap { |p| p.update_column(:created_at, 1.hour.ago) } # rubocop:disable Rails/SkipsModelValidations
      velha = da_pasta(pasta_id: 'v').tap { |p| p.update_column(:created_at, 2.hours.ago) } # rubocop:disable Rails/SkipsModelValidations
      allow(Ramon::Peticionamento::AlertasDaPasta).to receive(:call).and_call_original
      get url, headers: headers, as: :json
      expect(response.parsed_body['payload'].pluck('id')).to eq([velha.id, nova.id, rascunho.id])
      expect(response.parsed_body['payload'].first).not_to have_key('alertas')
      expect(Ramon::Peticionamento::AlertasDaPasta).not_to have_received(:call)
    end
  end
end
