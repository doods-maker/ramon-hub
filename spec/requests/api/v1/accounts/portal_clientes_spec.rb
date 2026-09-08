require 'rails_helper'

RSpec.describe 'Portal Clientes API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:headers) { agent.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/portal_clientes" }

  before { allow(Ramon::PortalSyncService).to receive(:new).and_return(instance_double(Ramon::PortalSyncService, perform: [])) }

  it 'exige autenticação' do
    get base
    expect(response).to have_http_status(:unauthorized)
  end

  it 'cria o cliente, sincroniza e envia o convite' do
    expect do
      post base, params: { advbox_customer_id: 14_688_380, nome: 'Venicio Schmidt', cpf: '123.456.789-01', email: 'v@exemplo.com' }, headers: headers
    end.to have_enqueued_mail(Ramon::PortalMailer, :convite)
    expect(response).to have_http_status(:success)
    cliente = PortalCliente.last
    expect(cliente.convidado_em).to be_present
    expect(cliente.cpf).to eq '12345678901'
    expect(Ramon::PortalSyncService).to have_received(:new).with(cliente)
  end

  it 'e-mail duplicado devolve 422' do
    create(:portal_cliente, account: account, email: 'v@exemplo.com')
    post base, params: { advbox_customer_id: 1, nome: 'X', email: 'v@exemplo.com' }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'lista, reenvia convite e grava recado' do
    cliente = create(:portal_cliente, account: account, processos: [{ 'id' => 7, 'docs_pendentes' => [] }])
    get base, headers: headers
    expect(response.parsed_body['payload'].first['id']).to eq cliente.id

    expect { post "#{base}/#{cliente.id}/convidar", headers: headers }.to have_enqueued_mail(Ramon::PortalMailer, :convite)
    patch "#{base}/#{cliente.id}", params: { recados: { '7' => 'Leve os exames' } }, headers: headers, as: :json
    expect(cliente.reload.recados).to eq('7' => 'Leve os exames')
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
