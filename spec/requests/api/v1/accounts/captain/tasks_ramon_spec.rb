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

  describe 'Perguntar ao AdvBox' do
    let(:advbox_lawsuits) do
      { offset: 0, limit: 1000, totalCount: 1,
        data: [{ id: 42, process_number: '0000518-86.2012.5.12.0041',
                 type: 'AUXÍLIO POR INCAPACIDADE', group: 'PREVIDENCIÁRIO',
                 stage: 'AÇÃO PROTOCOLADA', step: 'JUDICIAL', responsible: 'FULANA',
                 customers: [{ name: 'CLIENTE TESTE' }] }] }.to_json
    end

    before do
      stub_request(:get, %r{app\.advbox\.com\.br/api/v1/lawsuits})
        .to_return(status: 200, body: advbox_lawsuits, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, %r{app\.advbox\.com\.br/api/v1/movements/42})
        .to_return(status: 200, body: { data: [{ date: '2026-05-15', title: 'Intimação', header: 'TRT12' }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, %r{app\.advbox\.com\.br/api/v1/publications/42})
        .to_return(status: 200, body: { data: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'responde com os dados do AdvBox e devolve o follow_up_context' do
      allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result('processo protocolado, aguardando'))
      with_modified_env ADVBOX_API_TOKEN: 'tok' do
        post "/api/v1/accounts/#{account.id}/captain/tasks/advbox",
             params: { conversation_display_id: conversation.display_id },
             headers: admin.create_new_auth_token, as: :json
      end
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['message']).to eq('processo protocolado, aguardando')
      expect(response.parsed_body['follow_up_context']['advbox']).to be(true)
      expect(response.parsed_body['follow_up_context']['contexto']).to include('0000518-86.2012.5.12.0041')
      expect(Ramon::LlmClient).to have_received(:complete).with(hash_including(provider: 'deepseek'))
    end

    it 'follow_up com contexto advbox continua a conversa sem rebuscar na API' do
      allow(Ramon::LlmClient).to receive(:complete).and_return(llm_result('sim, houve intimação em 15/05'))
      with_modified_env ADVBOX_API_TOKEN: 'tok' do
        post "/api/v1/accounts/#{account.id}/captain/tasks/follow_up",
             params: { conversation_display_id: conversation.display_id,
                       message: 'houve intimação?',
                       follow_up_context: { advbox: true, contexto: 'Cliente: X — processo Y',
                                            historico: [{ pergunta: 'panorama', resposta: 'ok' }] } },
             headers: admin.create_new_auth_token, as: :json
      end
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['message']).to eq('sim, houve intimação em 15/05')
      expect(WebMock).not_to have_requested(:get, /app\.advbox\.com\.br/)
    end

    it 'devolve 422 com mensagem clara sem o token do AdvBox' do
      with_modified_env ADVBOX_API_TOKEN: nil do
        post "/api/v1/accounts/#{account.id}/captain/tasks/advbox",
             params: { conversation_display_id: conversation.display_id },
             headers: admin.create_new_auth_token, as: :json
      end
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('ADVBOX_API_TOKEN')
    end

    it 'devolve 422 quando o cliente não tem processos no AdvBox' do
      stub_request(:get, %r{app\.advbox\.com\.br/api/v1/lawsuits})
        .to_return(status: 200, body: { data: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
      with_modified_env ADVBOX_API_TOKEN: 'tok' do
        post "/api/v1/accounts/#{account.id}/captain/tasks/advbox",
             params: { conversation_display_id: conversation.display_id },
             headers: admin.create_new_auth_token, as: :json
      end
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('Nenhum processo')
    end
  end
end
