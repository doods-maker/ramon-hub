require 'rails_helper'

# Aba "Agente Claude" das Execuções (I-EX4): a trilha de agente_execucoes, mais
# nova primeiro, e o uso do teto de hoje (dia de Brasília). Roda no CI FOSS.
RSpec.describe 'Ramon Agente Execucoes API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_agente_execucoes" }

  it 'lista a trilha mais nova primeiro, com caso, conversa e acoes, e o uso de hoje' do
    lead = create(:lead, account: account, name: 'Maria Souza')
    conversa = create(:conversation, account: account)
    travel_to Time.zone.parse('2026-10-07 13:00:00') do # 10:00 em Brasília
      account.agente_execucoes.create!(pedido: 'ontem', status: 'ok', created_at: 1.day.ago)
      account.agente_execucoes.create!(pedido: 'sem cota', status: 'cap', resumo: 'Cap diário atingido (30)')
      account.agente_execucoes.create!(pedido: 'resuma o caso', status: 'erro', resumo: 'falhou', lead: lead,
                                       conversation: conversa, acoes: [{ 'tipo' => 'drive', 'ref' => 'https://drive/x' }],
                                       duracao_ms: 4200, modelo: 'opus', esforco: 'low')
      get url, headers: agent.create_new_auth_token, as: :json
    end

    body = response.parsed_body
    expect(response).to have_http_status(:success)
    expect(body['items'].pluck('pedido')).to eq(['resuma o caso', 'sem cota', 'ontem'])
    expect(body['items'].first).to include('lead_id' => lead.id, 'lead_nome' => 'Maria Souza',
                                           'conversa_display_id' => conversa.display_id, 'duracao_ms' => 4200,
                                           'acoes' => [{ 'tipo' => 'drive', 'ref' => 'https://drive/x' }])
    expect(body['resumo']).to eq('hoje' => 1, 'teto' => 30, 'problemas_hoje' => 2)
  end

  it 'nao vaza execucao de outra conta' do
    create(:account).agente_execucoes.create!(pedido: 'de outra conta', status: 'ok')

    get url, headers: agent.create_new_auth_token, as: :json

    expect(response.parsed_body['items']).to be_empty
  end

  it 'exige autenticacao' do
    get url, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
