require 'rails_helper'

RSpec.describe 'Captain Tool Runs API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/captain_tool_runs" }

  def registrar(tool_name, status: 'ok', conta: account)
    Captain::ToolRun.create!(account_id: conta.id, tool_name: tool_name, status: status,
                             params: { 'lead' => '1' }, resultado: 'resultado', duration_ms: 12)
  end

  it 'lista as execucoes mais recentes primeiro, com resumo de 24h' do
    registrar('checar_prescricao')
    ultima = registrar('calcular_beneficio', status: 'erro')

    get url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['items'].first).to include('id' => ultima.id, 'tool_name' => 'calcular_beneficio', 'status' => 'erro')
    expect(body['resumo']).to include('total_24h' => 2, 'erros_24h' => 1)
    expect(body['resumo']['tools']).to eq(%w[calcular_beneficio checar_prescricao])
  end

  it 'filtra por tool e por status' do
    registrar('checar_prescricao')
    registrar('checar_prescricao', status: 'erro')
    registrar('calcular_beneficio')

    get url, params: { tool_name: 'checar_prescricao', status: 'erro' }, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['items'].pluck('tool_name')).to eq(['checar_prescricao'])
  end

  it 'nao vaza execucao de outra conta' do
    registrar('checar_prescricao', conta: create(:account))

    get url, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['items']).to be_empty
  end

  it 'devolve o catalogo com nome e nivel de cada ferramenta', if: ChatwootApp.enterprise? do
    get url, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['catalogo']).to include({ 'id' => 'mover_etapa', 'title' => 'Mover de etapa', 'nivel' => 'sugestao' })
  end

  it 'devolve o nome do caso e o numero da conversa de cada linha (I-EX2)' do
    lead = create(:lead, account: account, name: 'Maria Souza')
    conversa = create(:conversation, account: account)
    Captain::ToolRun.create!(account_id: account.id, tool_name: 'mover_etapa', status: 'ok',
                             lead_id: lead.id, conversation_id: conversa.id)

    get url, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['items'].first).to include('lead_nome' => 'Maria Souza',
                                                           'conversa_display_id' => conversa.display_id)
  end

  it 'devolve o nome do assistente', if: ChatwootApp.enterprise? do
    assistente = create(:captain_assistant, account: account, name: 'Atendimento')
    Captain::ToolRun.create!(account_id: account.id, assistant_id: assistente.id, tool_name: 'faq_lookup', status: 'ok')

    get url, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['items'].first['assistente_nome']).to eq('Atendimento')
  end

  it 'exige autenticacao' do
    get url, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
