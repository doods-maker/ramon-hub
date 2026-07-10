require 'rails_helper'

RSpec.describe 'Public ADVBOX Webhooks API', type: :request do
  let(:account) { create(:account) }
  let(:token) { 'token-advbox-teste' }
  let(:payload) { { event: 'stage.changed', process: { stage: 'REQUERIMENTO PROTOCOLADO' } } }

  def post_webhook(body, authorization: "Bearer #{token}", env_token: token)
    with_modified_env(ADVBOX_WEBHOOK_TOKEN: env_token, RAMON_LEAD_CAPTURE_ACCOUNT_ID: account.id.to_s) do
      post '/public/api/v1/advbox_webhooks', params: body.to_json,
                                             headers: { 'CONTENT_TYPE' => 'application/json', 'Authorization' => authorization }
    end
  end

  describe 'POST /public/api/v1/advbox_webhooks' do
    it 'rejeita token errado com 401 sem capturar nada' do
      expect { post_webhook(payload, authorization: 'Bearer errado') }.not_to change(AdvboxEvent, :count)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejeita quando o token não está configurado no servidor' do
      post_webhook(payload, env_token: nil)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'aceita o token cru sem o prefixo Bearer (campo Autorização do Flowter)' do
      post_webhook(payload, authorization: token)
      expect(response).to have_http_status(:ok)
    end

    it 'captura o payload cru e enfileira o processamento' do
      expect { post_webhook(payload) }
        .to change(AdvboxEvent, :count).by(1)
        .and have_enqueued_job(Ramon::AdvboxEventJob)

      event = AdvboxEvent.find_by(account: account)
      expect(event.status).to eq 'received'
      expect(event.payload.dig('process', 'stage')).to eq 'REQUERIMENTO PROTOCOLADO'
    end

    it 'reentrega com corpo idêntico não duplica o evento (idempotência)' do
      post_webhook(payload)
      expect { post_webhook(payload) }.not_to change(AdvboxEvent, :count)
      expect(response).to have_http_status(:ok)
    end

    it 'corpo não-JSON é capturado mesmo assim (modo captura)' do
      with_modified_env(ADVBOX_WEBHOOK_TOKEN: token, RAMON_LEAD_CAPTURE_ACCOUNT_ID: account.id.to_s) do
        post '/public/api/v1/advbox_webhooks', params: { etapa: 'CONTRATO FECHADO' },
                                               headers: { 'Authorization' => "Bearer #{token}" }
      end
      expect(response).to have_http_status(:ok)
      expect(AdvboxEvent.find_by(account: account).payload['etapa']).to eq 'CONTRATO FECHADO'
    end
  end
end
