require 'rails_helper'

RSpec.describe 'Public ZapSign Webhooks API', type: :request do
  let(:assinatura) { create(:portal_assinatura, doc_token: 'doc-1') }
  let(:secret) { 'segredo' }

  def post_webhook(body, header: secret, env: secret)
    with_modified_env(ZAPSIGN_WEBHOOK_SECRET: env) do
      post '/public/api/v1/zapsign_webhooks', params: body.to_json,
                                              headers: { 'CONTENT_TYPE' => 'application/json', 'X-Ramon-Secret' => header }
    end
  end

  it 'rejeita segredo errado ou ausente no servidor' do
    post_webhook({ token: 'doc-1' }, header: 'x')
    expect(response).to have_http_status(:unauthorized)
    post_webhook({ token: 'doc-1' }, env: nil)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'token conhecido enfileira a conferência; desconhecido responde 200 sem job' do
    assinatura
    expect { post_webhook({ token: 'doc-1', event_type: 'doc_signed' }) }.to have_enqueued_job(Ramon::ZapsignStatusJob).with(assinatura.id)
    expect { post_webhook({ token: 'outro' }) }.not_to have_enqueued_job(Ramon::ZapsignStatusJob)
    expect(response).to have_http_status(:ok)
  end
end
