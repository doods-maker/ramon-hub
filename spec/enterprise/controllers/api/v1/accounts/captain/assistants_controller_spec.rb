require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::Assistants', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'GET /api/v1/accounts/{account.id}/captain/assistants' do
    context 'when it is an un-authenticated user' do
      it 'does not fetch assistants' do
        get "/api/v1/accounts/#{account.id}/captain/assistants",
            as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      it 'fetches assistants for the account' do
        create_list(:captain_assistant, 3, account: account)
        get "/api/v1/accounts/#{account.id}/captain/assistants",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response[:payload].length).to eq(3)
        expect(json_response[:meta]).to eq(
          { total_count: 3, page: 1 }
        )
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/captain/assistants/{id}' do
    let(:assistant) { create(:captain_assistant, account: account) }

    context 'when it is an un-authenticated user' do
      it 'does not fetch the assistant' do
        get "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
            as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      it 'fetches the assistant' do
        get "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(json_response[:id]).to eq(assistant.id)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/captain/assistants' do
    let(:valid_attributes) do
      {
        assistant: {
          name: 'New Assistant',
          description: 'Assistant Description',
          response_guidelines: ['Be helpful', 'Be concise'],
          guardrails: ['No harmful content', 'Stay on topic'],
          config: {
            product_name: 'Chatwoot',
            feature_faq: true,
            feature_memory: false,
            feature_citation: true
          }
        }
      }
    end

    context 'when it is an un-authenticated user' do
      it 'does not create an assistant' do
        post "/api/v1/accounts/#{account.id}/captain/assistants",
             params: valid_attributes,
             as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      it 'does not create an assistant' do
        post "/api/v1/accounts/#{account.id}/captain/assistants",
             params: valid_attributes,
             headers: agent.create_new_auth_token,
             as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an admin' do
      it 'creates a new assistant' do
        expect do
          post "/api/v1/accounts/#{account.id}/captain/assistants",
               params: valid_attributes,
               headers: admin.create_new_auth_token,
               as: :json
        end.to change(Captain::Assistant, :count).by(1)

        expect(json_response[:name]).to eq('New Assistant')
        expect(json_response[:response_guidelines]).to eq(['Be helpful', 'Be concise'])
        expect(json_response[:guardrails]).to eq(['No harmful content', 'Stay on topic'])
        expect(json_response[:config][:product_name]).to eq('Chatwoot')
        expect(json_response[:config][:feature_citation]).to be(true)
        expect(response).to have_http_status(:success)
      end

      it 'creates an assistant with feature_citation disabled' do
        attributes_with_disabled_citation = valid_attributes.deep_dup
        attributes_with_disabled_citation[:assistant][:config][:feature_citation] = false

        expect do
          post "/api/v1/accounts/#{account.id}/captain/assistants",
               params: attributes_with_disabled_citation,
               headers: admin.create_new_auth_token,
               as: :json
        end.to change(Captain::Assistant, :count).by(1)

        expect(json_response[:config][:feature_citation]).to be(false)
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/captain/assistants/{id}' do
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:update_attributes) do
      {
        assistant: {
          name: 'Updated Assistant',
          response_guidelines: ['Updated guideline'],
          guardrails: ['Updated guardrail'],
          config: {
            feature_citation: false
          }
        }
      }
    end

    context 'when it is an un-authenticated user' do
      it 'does not update the assistant' do
        patch "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
              params: update_attributes,
              as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      it 'does not update the assistant' do
        patch "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
              params: update_attributes,
              headers: agent.create_new_auth_token,
              as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an admin' do
      it 'updates the assistant' do
        patch "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
              params: update_attributes,
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(json_response[:name]).to eq('Updated Assistant')
        expect(json_response[:response_guidelines]).to eq(['Updated guideline'])
        expect(json_response[:guardrails]).to eq(['Updated guardrail'])
      end

      it 'updates only response_guidelines when only that is provided' do
        assistant.update!(response_guidelines: ['Original guideline'], guardrails: ['Original guardrail'])
        original_name = assistant.name

        patch "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
              params: { assistant: { response_guidelines: ['New guideline only'] } },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(json_response[:name]).to eq(original_name)
        expect(json_response[:response_guidelines]).to eq(['New guideline only'])
        expect(json_response[:guardrails]).to eq(['Original guardrail'])
      end

      it 'updates only guardrails when only that is provided' do
        assistant.update!(response_guidelines: ['Original guideline'], guardrails: ['Original guardrail'])
        original_name = assistant.name

        patch "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
              params: { assistant: { guardrails: ['New guardrail only'] } },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(json_response[:name]).to eq(original_name)
        expect(json_response[:response_guidelines]).to eq(['Original guideline'])
        expect(json_response[:guardrails]).to eq(['New guardrail only'])
      end

      it 'updates feature_citation config' do
        assistant.update!(config: { 'feature_citation' => true })

        patch "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
              params: { assistant: { config: { feature_citation: false } } },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(json_response[:config][:feature_citation]).to be(false)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/captain/assistants/{id}' do
    let!(:assistant) { create(:captain_assistant, account: account) }

    context 'when it is an un-authenticated user' do
      it 'does not delete the assistant' do
        delete "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
               as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      it 'delete the assistant' do
        delete "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
               headers: agent.create_new_auth_token,
               as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an admin' do
      it 'deletes the assistant' do
        expect do
          delete "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}",
                 headers: admin.create_new_auth_token,
                 as: :json
        end.to change(Captain::Assistant, :count).by(-1)

        expect(response).to have_http_status(:no_content)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/captain/assistants/{id}/playground' do
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:valid_params) do
      {
        message_content: 'Hello assistant',
        message_history: [
          { role: 'user', content: 'Previous message' },
          { role: 'assistant', content: 'Previous response', agent_name: 'billing_scenario' }
        ]
      }
    end
    let(:chat_service) { instance_double(Captain::Llm::AssistantChatService) }
    let(:agent_runner_service) { instance_double(Captain::Assistant::AgentRunnerService) }

    context 'when it is an un-authenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/playground",
             params: valid_params,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when captain v2 is disabled' do
      it 'generates a response with the legacy assistant chat service' do
        allow(Captain::Llm::AssistantChatService).to receive(:new).with(
          assistant: assistant,
          source: 'playground'
        ).and_return(chat_service)
        allow(chat_service).to receive(:generate_response).and_return({ content: 'Assistant response' })
        expect(Captain::Assistant::AgentRunnerService).not_to receive(:new)

        post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/playground",
             params: valid_params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(chat_service).to have_received(:generate_response).with(
          additional_message: valid_params[:message_content],
          message_history: valid_params[:message_history]
        )
        expect(json_response[:content]).to eq('Assistant response')
      end

      it 'uses empty array as default' do
        params_without_history = { message_content: 'Hello assistant' }
        allow(Captain::Llm::AssistantChatService).to receive(:new).with(
          assistant: assistant,
          source: 'playground'
        ).and_return(chat_service)
        allow(chat_service).to receive(:generate_response).and_return({ content: 'Assistant response' })
        expect(Captain::Assistant::AgentRunnerService).not_to receive(:new)

        post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/playground",
             params: params_without_history,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(chat_service).to have_received(:generate_response).with(
          additional_message: params_without_history[:message_content],
          message_history: []
        )
      end
    end

    context 'when captain v2 is enabled' do
      before do
        account.enable_features('captain_integration_v2')
      end

      it 'generates a response with the agent runner service' do
        allow(Captain::Assistant::AgentRunnerService).to receive(:new).with(
          hash_including(assistant: assistant, source: 'playground')
        ).and_return(agent_runner_service)
        allow(agent_runner_service).to receive(:generate_response).and_return({ response: 'Assistant response' })
        expect(Captain::Llm::AssistantChatService).not_to receive(:new)

        post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/playground",
             params: valid_params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(agent_runner_service).to have_received(:generate_response).with(
          message_history: valid_params[:message_history] + [{ role: 'user', content: valid_params[:message_content] }]
        )
        expect(json_response[:response]).to eq('Assistant response')
      end

      it 'does not duplicate the latest user message if it is already in history' do
        params_with_latest_message = {
          message_content: 'Hello assistant',
          message_history: [{ role: 'user', content: 'Hello assistant' }]
        }
        allow(Captain::Assistant::AgentRunnerService).to receive(:new).with(
          hash_including(assistant: assistant, source: 'playground')
        ).and_return(agent_runner_service)
        allow(agent_runner_service).to receive(:generate_response).and_return({ response: 'Assistant response' })

        post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/playground",
             params: params_with_latest_message,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(agent_runner_service).to have_received(:generate_response).with(
          message_history: params_with_latest_message[:message_history]
        )
      end

      it 'devolve as ferramentas que rodaram, com nome e erro (I-PG2)' do
        allow(Captain::Assistant::AgentRunnerService).to receive(:new) do |**args|
          coletor = args[:callbacks][:on_tool_complete]
          coletor.call('captain-tools-mover_etapa', 'movido', nil)
          coletor.call('captain-tools-checar_prescricao', Captain::Tools::BasePublicTool::ERRO_NA_TOOL, nil)
          agent_runner_service
        end
        allow(agent_runner_service).to receive(:generate_response).and_return({ 'response' => 'ok' })

        post "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/playground",
             params: valid_params, headers: agent.create_new_auth_token, as: :json

        expect(json_response[:ferramentas]).to eq(
          [{ id: 'mover_etapa', title: 'Mover de etapa', nivel: 'sugestao', status: 'ok' },
           { id: 'checar_prescricao', title: 'Checar prescrição', nivel: 'consulta', status: 'erro' }]
        )
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/captain/assistants/{id}/texto_final' do
    it 'junta o texto do assistente e o de cada skill ligada (I-CF6)', :aggregate_failures do
      assistant = create(:captain_assistant, account: account, guardrails: ['Nunca prometa prazo do INSS.'])
      create(:captain_scenario, assistant: assistant, account: account, title: 'Funil hoje')
      create(:captain_scenario, assistant: assistant, account: account, title: 'Desligada', enabled: false)

      get "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/texto_final",
          headers: agent.create_new_auth_token, as: :json

      expect(json_response[:assistente]).to include('Nunca prometa prazo do INSS.')
      expect(json_response[:skills].pluck(:title)).to eq(['Funil hoje'])
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/captain/assistants/stats' do
    it 'devolve um cartao por assistente com skills, FAQs, caixas e conversas abertas por modo' do
      atendimento = create(:captain_assistant, account: account, name: 'Atendimento')
      copiloto = create(:captain_assistant, account: account, name: 'Copiloto')
      inbox = create(:inbox, account: account)
      create(:captain_inbox, captain_assistant: atendimento, inbox: inbox)
      create(:captain_scenario, assistant: atendimento, account: account)
      create(:captain_scenario, assistant: atendimento, account: account, enabled: false)
      create(:captain_assistant_response, assistant: atendimento, account: account)
      create(:captain_assistant_response, assistant: atendimento, account: account, status: :pending)
      create(:conversation, account: account, inbox: inbox, custom_attributes: { 'copiloto_modo' => 'manual' })
      create(:conversation, account: account, inbox: inbox)
      create(:conversation, account: account, inbox: inbox, custom_attributes: { 'copiloto_modo' => 'xyz' })
      create(:conversation, account: account, inbox: inbox, status: :resolved)

      with_modified_env RAMON_COPILOTO_MODO_DEFAULT: 'piloto_limitado' do
        get "/api/v1/accounts/#{account.id}/captain/assistants/stats", headers: agent.create_new_auth_token, as: :json
      end

      expect(response).to have_http_status(:success)
      cartoes = json_response[:payload].index_by { |cartao| cartao[:id] }
      expect(cartoes[atendimento.id]).to include(publico: 'lead', skills_ativas: 1, faqs_aprovadas: 1, faqs_pendentes: 1,
                                                 conversas_por_modo: { manual: 1, piloto_limitado: 2 })
      expect(cartoes[atendimento.id][:caixas].pluck(:id)).to eq([inbox.id])
      expect(cartoes[copiloto.id]).to include(publico: 'equipe', skills_ativas: 0, caixas: [], conversas_por_modo: {})
    end

    it 'exige autenticacao' do
      get "/api/v1/accounts/#{account.id}/captain/assistants/stats", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/captain/assistants/{id}/buscar_faq' do
    let(:assistant) { create(:captain_assistant, account: account) }

    around { |example| with_modified_env(RAMON_FAQ_BUSCA: 'texto') { example.run } }

    before do
      create(:captain_assistant_response, assistant: assistant, account: account, tese: 'auxilio-acidente',
                                          question: 'Posso continuar trabalhando recebendo auxílio-acidente?',
                                          answer: 'Pode, é compatível com o trabalho.')
      create(:captain_assistant_response, assistant: assistant, account: account, question: 'Quanto custa?',
                                          answer: '30% dos atrasados + 3 benefícios.')
      create(:captain_assistant_response, assistant: assistant, account: account, status: :pending,
                                          question: 'Posso continuar trabalhando e receber o BPC?', answer: 'Depende da renda.')
    end

    def buscar(pergunta)
      get "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/buscar_faq",
          params: { q: pergunta }, headers: agent.create_new_auth_token, as: :json
      json_response[:payload]
    end

    it 'devolve as FAQs aprovadas deste assistente que a busca do faq_lookup acharia' do
      faqs = buscar('posso continuar trabalhando')

      expect(response).to have_http_status(:success)
      expect(faqs.pluck(:question)).to eq(['Posso continuar trabalhando recebendo auxílio-acidente?'])
      expect(faqs.first).to include(tese: 'auxilio-acidente', answer: 'Pode, é compatível com o trabalho.')
    end

    it 'pergunta vazia ou sem nada parecido volta lista vazia' do
      expect(buscar('   ')).to eq([])
      expect(buscar('foguete lunar')).to eq([])
    end
  end
end
