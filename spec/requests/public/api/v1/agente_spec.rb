require 'rails_helper'

RSpec.describe 'Public Agente API', type: :request do
  let(:account) { create(:account) }
  let(:token) { 'agente-teste' }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Maria', phone_number: '+5548999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:headers) { { 'CONTENT_TYPE' => 'application/json' } }

  around { |ex| with_modified_env(RAMON_AGENTE_TOKEN: token) { ex.run } }

  it 'rejeita token errado' do
    get "/public/api/v1/agente/contexto?token=errado&account_id=#{account.id}&conversation_id=#{conversation.display_id}"
    expect(response).to have_http_status(:unauthorized)
  end

  it 'devolve contexto com mensagens, contato e lead' do
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming, content: 'oi, sofri acidente')
    lead = create(:lead, account: account, contact: contact, conversation: conversation)
    get "/public/api/v1/agente/contexto?token=#{token}&account_id=#{account.id}&conversation_id=#{conversation.display_id}"
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body['conversa']['mensagens'].first['texto']).to eq 'oi, sofri acidente'
    expect(body['contato']['nome']).to eq 'Maria'
    expect(body['lead_id']).to eq lead.id
  end

  it 'cria nota privada como AgentBot Claude' do
    bot = create(:agent_bot, account: account, name: 'Claude')
    post "/public/api/v1/agente/nota?token=#{token}",
         params: { account_id: account.id, conversation_id: conversation.display_id, texto: '🤖 ok' }.to_json, headers: headers
    expect(response).to have_http_status(:created)
    msg = conversation.messages.last
    expect(msg).to have_attributes(private: true, content: '🤖 ok', sender: bot)
  end

  it 'registra execução' do
    post "/public/api/v1/agente/execucoes?token=#{token}",
         params: { account_id: account.id, conversation_id: conversation.display_id, pedido: 'resumo', status: 'ok',
                   acoes: [{ tipo: 'nota' }] }.to_json, headers: headers
    expect(response).to have_http_status(:created)
    expect(AgenteExecucao.last).to have_attributes(pedido: 'resumo', status: 'ok', conversation_id: conversation.id,
                                                   acoes: [{ 'tipo' => 'nota' }])
  end

  it 'arquivo: 503 sem Drive configurado' do
    lead = create(:lead, account: account, contact: contact, conversation: conversation)
    with_modified_env(RAMON_DRIVE_CREDENTIALS: nil) do
      post "/public/api/v1/agente/arquivo?token=#{token}",
           params: { account_id: account.id, lead_id: lead.id, nome: 'd.md', conteudo: '# x' }.to_json, headers: headers
    end
    expect(response).to have_http_status(:service_unavailable)
  end

  it 'arquivo: sobe no Drive na pasta do lead' do
    lead = create(:lead, account: account, contact: contact, conversation: conversation)
    with_modified_env(RAMON_DRIVE_CREDENTIALS: '/x.json', RAMON_DRIVE_ROOT_ID: 'root') do
      allow(Ramon::DriveClient).to receive(:ensure_folder).and_return('pasta1')
      allow(Ramon::DriveClient).to receive(:upload).and_return('file9')
      post "/public/api/v1/agente/arquivo?token=#{token}",
           params: { account_id: account.id, lead_id: lead.id, nome: 'd.md', conteudo: '# x' }.to_json, headers: headers
    end
    expect(response.parsed_body).to include('file_id' => 'file9')
  end
end
