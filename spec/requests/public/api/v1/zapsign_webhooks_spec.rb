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

  it 'casa o contrato do lead pelo doc_token e enfileira a conferência do lead' do
    lead = create(:lead, custom_attributes: { 'zapsign' => { 'doc_token' => 'doc-lead', 'sign_url' => 'https://x' } })

    expect { post_webhook({ token: 'doc-lead', event_type: 'doc_signed' }) }
      .to have_enqueued_job(Ramon::ZapsignLeadStatusJob).with(lead.id, 'doc-lead')
    expect { post_webhook({ token: '' }) }.not_to have_enqueued_job(Ramon::ZapsignLeadStatusJob)
  end

  it 'gatilho comum (N1 = B): enfileira a conferência de sempre e o fluxo comum de "Assinatura do Painel" ouve' do
    comum = fluxo_publicado(assinatura.portal_cliente.account, grafo_linear({ 'tipo' => 'assinatura_painel' }))
    expect { post_webhook({ token: 'doc-1' }) }.to have_enqueued_job(Ramon::ZapsignStatusJob).with(assinatura.id)
    expect(comum.execucoes.sole).to have_attributes(alvo: assinatura, ensaio: false)
  end
end
