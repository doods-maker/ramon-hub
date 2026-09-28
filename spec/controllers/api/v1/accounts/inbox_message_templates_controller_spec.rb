require 'rails_helper'

RSpec.describe Api::V1::Accounts::InboxMessageTemplatesController, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:whatsapp_inbox) { create(:inbox, channel: whatsapp_channel, account: account) }
  let(:templates_url) { 'https://graph.facebook.com/v14.0/123456789/message_templates' }
  let(:url) { "/api/v1/accounts/#{account.id}/inboxes/#{whatsapp_inbox.id}/message_templates" }
  let(:template) do
    { name: 'confirmacao_atendimento', category: 'UTILITY', language: 'pt_BR',
      body: 'Olá {{1}}, confirmamos seu atendimento em {{2}}.', examples: ['Maria', 'terça às 14h'] }
  end

  before { create(:inbox_member, user: agent, inbox: whatsapp_inbox) }

  it 'creates the template on Meta with body examples and resyncs' do
    create_stub = stub_request(:post, templates_url).with(
      body: {
        name: 'confirmacao_atendimento', category: 'UTILITY', language: 'pt_BR',
        components: [{ type: 'BODY', text: template[:body], example: { body_text: [['Maria', 'terça às 14h']] } }]
      }
    ).to_return(status: 200, body: { id: '999', status: 'PENDING' }.to_json, headers: { 'Content-Type' => 'application/json' })
    sync_stub = stub_request(:get, "#{templates_url}?access_token=test_key")
                .to_return(status: 200, body: { data: [{ name: 'confirmacao_atendimento', status: 'PENDING' }] }.to_json,
                           headers: { 'Content-Type' => 'application/json' })

    post url, params: { template: template }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to eq('id' => '999', 'status' => 'PENDING')
    expect(create_stub).to have_been_requested
    expect(sync_stub).to have_been_requested
    expect(whatsapp_channel.reload.message_templates.first['name']).to eq('confirmacao_atendimento')
  end

  it 'returns the Meta error message when creation fails' do
    stub_request(:post, templates_url)
      .to_return(status: 400, body: { error: { message: 'raw', error_user_msg: 'Nome já existe' } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })

    post url, params: { template: template }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('Nome já existe')
  end

  it 'rejects unsupported categories without calling Meta' do
    post url, params: { template: template.merge(category: 'AUTHENTICATION') }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(a_request(:post, templates_url)).not_to have_been_made
  end

  it 'forbids agents' do
    post url, params: { template: template }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects non WhatsApp Cloud inboxes' do
    web_inbox = create(:inbox, account: account)

    post "/api/v1/accounts/#{account.id}/inboxes/#{web_inbox.id}/message_templates",
         params: { template: template }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:bad_request)
  end
end
