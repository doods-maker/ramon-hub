require 'rails_helper'

RSpec.describe 'Ramon Reunioes API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:audio) { Rack::Test::UploadedFile.new(StringIO.new('fake-audio'), 'audio/webm', original_filename: 'reuniao.webm') }

  describe 'POST /api/v1/accounts/:id/ramon_reunioes' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/ramon_reunioes"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as agent' do
      it 'creates the reuniao and enqueues the job' do
        expect do
          post "/api/v1/accounts/#{account.id}/ramon_reunioes",
               params: { audio: audio, titulo: 'Alinhamento', duracao_segundos: 90 },
               headers: agent.create_new_auth_token
        end.to have_enqueued_job(Ramon::ReuniaoAtaJob)
        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['status']).to eq('transcrevendo')
        expect(body['titulo']).to eq('Alinhamento')
        expect(Reuniao.last.audio).to be_attached
      end

      it 'rejects audio above the byte limit' do
        allow_any_instance_of(Rack::Test::UploadedFile).to receive(:size).and_return(26_000_000) # rubocop:disable RSpec/AnyInstance
        post "/api/v1/accounts/#{account.id}/ramon_reunioes",
             params: { audio: audio }, headers: agent.create_new_auth_token
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'rejects missing audio' do
        post "/api/v1/accounts/#{account.id}/ramon_reunioes",
             params: {}, headers: agent.create_new_auth_token
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'GET /api/v1/accounts/:id/ramon_reunioes' do
    it 'lists reunioes' do
      create(:reuniao, account: account, titulo: 'Semanal')
      get "/api/v1/accounts/#{account.id}/ramon_reunioes", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('titulo')).to include('Semanal')
    end
  end

  describe 'POST /api/v1/accounts/:id/ramon_reunioes/:id/reprocessar' do
    it 'requeues when status is erro' do
      reuniao = create(:reuniao, account: account, status: 'erro', erro: 'boom')
      expect do
        post "/api/v1/accounts/#{account.id}/ramon_reunioes/#{reuniao.id}/reprocessar",
             headers: agent.create_new_auth_token
      end.to have_enqueued_job(Ramon::ReuniaoAtaJob).with(reuniao.id)
      expect(reuniao.reload).to have_attributes(status: 'transcrevendo', erro: nil)
    end

    it 'refuses when status is not erro' do
      reuniao = create(:reuniao, account: account, status: 'pronta')
      post "/api/v1/accounts/#{account.id}/ramon_reunioes/#{reuniao.id}/reprocessar",
           headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'DELETE /api/v1/accounts/:id/ramon_reunioes/:id' do
    it 'destroys the reuniao' do
      reuniao = create(:reuniao, account: account)
      delete "/api/v1/accounts/#{account.id}/ramon_reunioes/#{reuniao.id}",
             headers: agent.create_new_auth_token
      expect(response).to have_http_status(:no_content)
      expect(Reuniao.exists?(reuniao.id)).to be(false)
    end
  end
end
