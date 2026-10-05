require 'rails_helper'

RSpec.describe 'Portal Clientes API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:headers) { agent.create_new_auth_token }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:admin_headers) { admin.create_new_auth_token }

  def na_recepcao(user)
    time = create(:team, account: account, name: Chegada::RECEPCAO)
    create(:team_member, team: time, user: user)
  end
  let(:base) { "/api/v1/accounts/#{account.id}/portal_clientes" }

  before { allow(Ramon::PortalSyncService).to receive(:new).and_return(instance_double(Ramon::PortalSyncService, perform: [])) }

  it 'exige autenticação' do
    get base
    expect(response).to have_http_status(:unauthorized)
  end

  it 'lista com o funil do piloto (entraram = 1+ dia, voltaram = 2+ dias)' do
    create(:portal_cliente, account: account, convidado_em: 2.days.ago, dias_acesso: 3)
    create(:portal_cliente, account: account, convidado_em: 2.days.ago, dias_acesso: 1)
    create(:portal_cliente, account: account, convidado_em: nil)
    get base, headers: headers
    expect(response.parsed_body['metricas']).to include('convidados' => 2, 'entraram' => 2, 'voltaram' => 1, 'enviaram' => 0)
  end

  it 'cria o cliente, sincroniza, gera a senha provisória (devolvida uma vez) e envia o convite' do
    with_modified_env SMTP_ADDRESS: 'smtp.exemplo.com' do
      expect do
        post base, headers: headers,
                   params: { advbox_customer_id: 14_688_380, nome: 'Venicio Schmidt', cpf: '123.456.789-01', email: 'v@exemplo.com' }
      end.to have_enqueued_mail(Ramon::PortalMailer, :convite)
    end
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['email']).to eq('status' => 'enviado', 'para' => 'v@exemplo.com')
    cliente = PortalCliente.last
    expect(cliente.convidado_em).to be_present
    expect(cliente.cpf).to eq '12345678901'
    senha = response.parsed_body['senha_provisoria']
    expect(senha).to match(/\A\d{6}\z/)
    expect(cliente.authenticate_senha(senha)).to be_truthy
    expect(Ramon::PortalSyncService).to have_received(:new).with(cliente)
  end

  it 'sem e-mail: cria, gera a senha e não enfileira convite' do
    expect do
      post base, params: { advbox_customer_id: 14_688_381, nome: 'Sem Email', cpf: '987.654.321-00', email: '' }, headers: headers
    end.not_to have_enqueued_mail(Ramon::PortalMailer, :convite)
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['senha_provisoria']).to match(/\A\d{6}\z/)
    expect(response.parsed_body['email']).to eq('status' => 'sem_email')
    expect(PortalCliente.last.email).to be_nil
  end

  it 'com e-mail mas sem servidor de e-mail: não enfileira e avisa sem_servidor' do
    with_modified_env SMTP_ADDRESS: nil do
      expect do
        post base, params: { advbox_customer_id: 14_688_382, nome: 'Com Email', cpf: '987.654.321-11', email: 'c@exemplo.com' }, headers: headers
      end.not_to have_enqueued_mail(Ramon::PortalMailer, :convite)
    end
    expect(response.parsed_body['email']).to eq('status' => 'sem_servidor', 'para' => 'c@exemplo.com')
    expect(response.parsed_body['mensagem']).to be_nil
  end

  it 'e-mail duplicado devolve 422' do
    create(:portal_cliente, account: account, email: 'v@exemplo.com')
    post base, params: { advbox_customer_id: 1, nome: 'X', cpf: '111.111.111-11', email: 'v@exemplo.com' }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'convidar de novo o mesmo cliente do ADVBOX atualiza a linha (conserta conta sem CPF) em vez de 422' do
    cliente = create(:portal_cliente, account: account, advbox_customer_id: 15_255_795, nome: 'Maria Teste', email: nil)
    cliente.update_column(:cpf, nil) # rubocop:disable Rails/SkipsModelValidations -- linha anterior ao login por CPF

    post base, params: { advbox_customer_id: 15_255_795, nome: 'Maria Teste Silva', cpf: '222.222.222-22', email: '' }, headers: headers
    expect(response).to have_http_status(:success)
    expect(PortalCliente.count).to eq 1
    expect(cliente.reload.attributes.slice('cpf', 'nome')).to eq('cpf' => '22222222222', 'nome' => 'Maria Teste Silva')
    expect(cliente.authenticate_senha(response.parsed_body['senha_provisoria'])).to be_truthy
  end

  it 'lista, reenvia convite e grava recado' do
    cliente = create(:portal_cliente, account: account, processos: [{ 'id' => 7, 'docs_pendentes' => [] }])
    get base, headers: headers
    expect(response.parsed_body['payload'].first['id']).to eq cliente.id

    with_modified_env SMTP_ADDRESS: 'smtp.exemplo.com' do
      expect { post "#{base}/#{cliente.id}/convidar", headers: headers }.to have_enqueued_mail(Ramon::PortalMailer, :convite)
    end
    expect(cliente.reload.authenticate_senha(response.parsed_body['senha_provisoria'])).to be_truthy
    patch "#{base}/#{cliente.id}", params: { recados: { '7' => 'Leve os exames' } }, headers: headers, as: :json
    expect(cliente.reload.recados).to eq('7' => 'Leve os exames')
  end

  it 'altera o e-mail e (admin) exclui a conta: envios somem, registro de acesso fica 6 meses com o CPF' do
    cliente = create(:portal_cliente, account: account, email: 'antigo@exemplo.com', cpf: '12345678901')
    cliente.envios.create!(lawsuit_id: 7, item: 'RG')
    cliente.acessos.create!(ip: '1.2.3.4')

    patch "#{base}/#{cliente.id}", params: { email: 'Novo@Exemplo.com' }, headers: headers, as: :json
    expect(cliente.reload.email).to eq 'novo@exemplo.com'

    delete "#{base}/#{cliente.id}", headers: headers
    expect(response).to have_http_status(:unauthorized)

    delete "#{base}/#{cliente.id}", headers: admin_headers
    expect(response).to have_http_status(:no_content)
    expect(PortalCliente.exists?(cliente.id)).to be false
    expect(PortalEnvio.where(portal_cliente_id: cliente.id)).to be_empty
    expect(PortalAcesso.where(portal_cliente_id: cliente.id).pluck(:cpf, :ip)).to eq [%w[12345678901 1.2.3.4]]
    expect(PortalEvento.where(portal_cliente_id: cliente.id).pluck(:acao, :user_id)).to include(['excluiu', admin.id])
  end

  it 'detalhe mostra o que o cliente vê na etapa (mesma tradução do portal) e marca a etapa interna' do
    cliente = create(:portal_cliente, account: account, processos: [
                       { 'id' => 1, 'etapa' => 'PERICIA AGENDADA', 'etapa_cliente' => 'PERICIA AGENDADA', 'docs_pendentes' => [] },
                       { 'id' => 2, 'etapa' => 'NEGADO / AVISAR CLIENTE', 'etapa_cliente' => 'REQUERIMENTO PROTOCOLADO', 'docs_pendentes' => [] }
                     ])
    get "#{base}/#{cliente.id}", headers: headers
    vistos = response.parsed_body['processos'].map { |p| p.values_at('cliente_ve', 'etapa_interna') }
    expect(vistos).to eq [['Perícia agendada', false], ['Pedido protocolado no INSS', true]]
  end

  it 'conta só o que falta (descontando o que o cliente já mandou) e lista cada documento com o link do Drive' do
    cliente = create(:portal_cliente, account: account, convidado_em: 1.day.ago, processos: [
                       { 'id' => 7, 'docs_pendentes' => [{ 'item' => 'RG', 'post_id' => 1 }, { 'item' => 'CNIS', 'post_id' => 1 }] }
                     ])
    cliente.envios.create!(lawsuit_id: 7, solicitacao_post_id: 1, item: 'RG', drive_file_id: 'abc')

    get base, headers: headers
    expect(response.parsed_body['payload'].first['docs_pendentes']).to eq 1
    expect(response.parsed_body['metricas']['docs_pedidos']).to eq 1

    get "#{base}/#{cliente.id}", headers: headers
    docs = response.parsed_body['processos'].first['documentos']
    expect(docs.map { |d| d.values_at('item', 'enviado') }).to eq [['RG', true], ['CNIS', false]]
    expect(response.parsed_body['envios'].first['drive_url']).to eq 'https://drive.google.com/file/d/abc'
  end

  it 'cancela o documento no ZapSign, marca cancelado (sai do "assinar" do cliente) e registra' do
    cliente = create(:portal_cliente, account: account)
    a = create(:portal_assinatura, portal_cliente: cliente, doc_token: 'doc-9')
    allow(Ramon::ZapsignClient).to receive(:refuse_doc)

    post "#{base}/#{cliente.id}/cancelar_assinatura", params: { assinatura_id: a.id }, headers: headers, as: :json
    expect(response).to have_http_status(:success)
    expect(Ramon::ZapsignClient).to have_received(:refuse_doc).with('doc-9', anything)
    expect(a.reload.status).to eq 'cancelado'
    expect(cliente.assinaturas.pendentes).to be_empty
    expect(response.parsed_body['eventos'].first['acao']).to eq 'cancelou_assinatura'
  end

  it 'ZapSign fora do ar ao cancelar: 503 e o documento segue pendente' do
    cliente = create(:portal_cliente, account: account)
    a = create(:portal_assinatura, portal_cliente: cliente)
    allow(Ramon::ZapsignClient).to receive(:refuse_doc).and_raise(Ramon::ZapsignClient::UnavailableError, 'fora')

    post "#{base}/#{cliente.id}/cancelar_assinatura", params: { assinatura_id: a.id }, headers: headers, as: :json
    expect(response).to have_http_status(:service_unavailable)
    expect(a.reload.status).to eq 'pendente'
  end

  it 'registra a trilha (quem fez o quê) e devolve o histórico no detalhe' do
    na_recepcao(agent)
    cliente = create(:portal_cliente, account: account, processos: [{ 'id' => 7, 'docs_pendentes' => [] }])
    post "#{base}/#{cliente.id}/convidar", headers: headers
    post "#{base}/#{cliente.id}/convidar", headers: headers
    patch "#{base}/#{cliente.id}", params: { recados: { '7' => 'Oi' } }, headers: headers, as: :json
    post "#{base}/#{cliente.id}/suspender", headers: headers

    get "#{base}/#{cliente.id}", headers: headers
    eventos = response.parsed_body['eventos']
    expect(eventos.pluck('acao')).to eq %w[suspendeu salvou_recado nova_senha convidou]
    expect(eventos.first['user_name']).to eq agent.name
  end

  describe 'suspender, reativar e senha nova de quem já tem acesso' do
    let(:cliente) { create(:portal_cliente, account: account, convidado_em: 1.day.ago) }

    it 'agente fora da recepção/controladoria não suspende nem gera senha nova; vê as permissões no index' do
      post "#{base}/#{cliente.id}/suspender", headers: headers
      expect(response).to have_http_status(:unauthorized)
      post "#{base}/#{cliente.id}/convidar", headers: headers
      expect(response).to have_http_status(:unauthorized)
      get base, headers: headers
      expect(response.parsed_body['permissoes']).to eq('gerir_acesso' => false, 'excluir' => false)
    end

    it 'recepção suspende (derruba a sessão, nada é apagado) e reativa' do
      na_recepcao(agent)
      chave = cliente.sessao_chave
      post "#{base}/#{cliente.id}/suspender", headers: headers
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['suspenso_em']).to be_present
      expect(cliente.reload.sessao_chave).not_to eq chave

      post "#{base}/#{cliente.id}/reativar", headers: headers
      expect(cliente.reload.suspenso?).to be false
      get base, headers: headers
      expect(response.parsed_body['permissoes']).to eq('gerir_acesso' => true, 'excluir' => false)
    end

    it 'controladoria também gera senha nova' do
      time = create(:team, account: account, name: 'controladoria')
      create(:team_member, team: time, user: agent)
      post "#{base}/#{cliente.id}/convidar", headers: headers
      expect(response).to have_http_status(:success)
    end
  end

  it 'cria o documento no ZapSign sem e-mail automático e guarda os tokens' do
    cliente = create(:portal_cliente, account: account, nome: 'Maria', email: 'm@exemplo.com')
    allow(Ramon::ZapsignClient).to receive(:create_doc_from_template)
      .with(hash_including(template_id: 'tpl', signer_name: 'Maria', signer_email: 'm@exemplo.com', send_automatic_email: false))
      .and_return('token' => 'doc-1', 'signers' => [{ 'token' => 'sig-1' }])
    allow(Ramon::ZapsignClient).to receive(:update_signer)

    post "#{base}/#{cliente.id}/assinatura", params: { template_id: 'tpl', nome: 'Procuração', variaveis: { '{{nome}}' => 'Maria' } },
                                             headers: headers, as: :json
    expect(response).to have_http_status(:success)
    a = cliente.assinaturas.last
    expect([a.doc_token, a.signer_token, a.status]).to eq %w[doc-1 sig-1 pendente]
    expect(Ramon::ZapsignClient).to have_received(:update_signer).with('sig-1', hash_including(auth_mode: 'assinaturaTela'))
  end
end
