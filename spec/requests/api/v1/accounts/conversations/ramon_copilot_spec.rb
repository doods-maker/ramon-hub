require 'rails_helper'

RSpec.describe 'Ramon Conversation Copilot API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/ramon_copilot" }

  def llm_result(content)
    Ramon::LlmClient::Result.new(content: content, input_tokens: 10, output_tokens: 5)
  end

  describe 'POST /api/v1/accounts/:account_id/conversations/:conversation_id/ramon_copilot' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post url, params: { mode: 'summary' }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      before do
        create(:message, account: account, conversation: conversation,
                         message_type: :incoming, content: 'Sofri um acidente em 2024')
      end

      it 'devolve o resumo gerado pelo LLM (mode=summary)' do
        allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result('resumo estruturado'))
        post url, params: { mode: 'summary' }, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
        expect(response.parsed_body['content']).to eq('resumo estruturado')
      end

      it 'devolve o rascunho gerado pelo LLM (mode=draft) sem criar mensagem na conversa' do
        allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result('Oi, tudo bem?'))
        expect do
          post url, params: { mode: 'draft' }, headers: admin.create_new_auth_token, as: :json
        end.not_to change(conversation.messages, :count)
        expect(response).to have_http_status(:success)
        expect(response.parsed_body['content']).to eq('Oi, tudo bem?')
      end

      it 'rejeita modo desconhecido com 422' do
        post url, params: { mode: 'enviar' }, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Modo inválido')
      end

      it 'devolve 422 com a mensagem quando o LLM está indisponível' do
        allow(Ramon::LlmClient).to receive(:complete)
          .and_raise(Ramon::LlmClient::MissingApiKeyError, 'ENV DEEPSEEK_API_KEY ausente')
        post url, params: { mode: 'summary' }, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to include('DEEPSEEK_API_KEY')
      end
    end

    context 'when the conversation has no text messages' do
      it 'devolve 422' do
        post url, params: { mode: 'summary' }, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to include('sem mensagens')
      end
    end
  end
end
