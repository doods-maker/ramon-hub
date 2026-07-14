require 'rails_helper'

RSpec.describe 'Captain Tasks (fork: copiloto da banca)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account) }

  def llm_result(content)
    Ramon::LlmClient::Result.new(content: content, input_tokens: 10, output_tokens: 5)
  end

  before do
    create(:message, account: account, conversation: conversation,
                     message_type: :incoming, content: 'Sofri um acidente em 2024')
  end

  it 'summarize delega ao copiloto da banca (DeepSeek + LGPD)' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result('resumo estruturado'))
    post "/api/v1/accounts/#{account.id}/captain/tasks/summarize",
         params: { conversation_display_id: conversation.display_id },
         headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['message']).to eq('resumo estruturado')
    expect(Ramon::LlmClient).to have_received(:complete).with(hash_including(provider: 'deepseek'))
  end

  it 'reply_suggestion delega ao copiloto da banca (modo rascunho)' do
    allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result('Oi, tudo bem?'))
    post "/api/v1/accounts/#{account.id}/captain/tasks/reply_suggestion",
         params: { conversation_display_id: conversation.display_id },
         headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['message']).to eq('Oi, tudo bem?')
  end

  it 'devolve 422 com a mensagem real quando o LLM está indisponível' do
    allow(Ramon::LlmClient).to receive(:complete)
      .and_raise(Ramon::LlmClient::MissingApiKeyError, 'ENV DEEPSEEK_API_KEY ausente')
    post "/api/v1/accounts/#{account.id}/captain/tasks/summarize",
         params: { conversation_display_id: conversation.display_id },
         headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('DEEPSEEK_API_KEY')
  end

  it 'devolve 422 para conversa inexistente' do
    post "/api/v1/accounts/#{account.id}/captain/tasks/summarize",
         params: { conversation_display_id: 999_999 },
         headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('não encontrada')
  end
end
