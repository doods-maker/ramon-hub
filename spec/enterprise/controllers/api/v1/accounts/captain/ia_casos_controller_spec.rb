require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::IaCasos', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/ia_casos" }
  let(:dados) do
    { titulo: 'A11 · quero falar com o Dr. Ramon', grupo: 'auxilio-acidente',
      mensagens: [{ role: 'user', content: 'quero falar com o Dr. Ramon' }],
      criterios: { handoff: 'sim', deve_usar: ['handoff', ''], deve_conter: ['equipe'], rubrica: 'Acolhe.' } }
  end

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  it 'agente nao ve nem cria casos', :aggregate_failures do
    get url, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    post url, params: { caso: dados }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(Captain::IaCaso.count).to eq(0)
  end

  it 'admin cria caso com criterios normalizados e lista com a estimativa', :aggregate_failures do
    post url, params: { caso: dados }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    caso = Captain::IaCaso.last
    expect(caso).to have_attributes(account_id: account.id, assistant_id: assistant.id, origem: 'usuario', ativo: true)
    expect(caso.criterios).to include('handoff' => 'sim', 'deve_usar' => ['handoff'], 'nao_deve_usar' => [], 'rubrica' => 'Acolhe.')

    get url, headers: admin.create_new_auth_token, as: :json
    expect(json_response[:payload].pluck(:id)).to eq([caso.id])
    expect(json_response[:estimativa]).to eq(casos: 1, custo_usd: 0.05, segundos: 20)
  end

  it 'recusa caso cuja ultima fala nao e do usuario' do
    dados[:mensagens] << { role: 'assistant', content: 'oi' }

    post url, params: { caso: dados }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'admin edita e apaga', :aggregate_failures do
    caso = Captain::IaCaso.create!(dados.merge(account: account, assistant: assistant))

    patch "#{url}/#{caso.id}", params: { caso: { ativo: false, criterios: { handoff: 'nao' } } }, headers: admin.create_new_auth_token, as: :json
    expect(caso.reload).to have_attributes(ativo: false)
    expect(caso.criterios['handoff']).to eq('nao')

    delete "#{url}/#{caso.id}", headers: admin.create_new_auth_token, as: :json
    expect(Captain::IaCaso.exists?(caso.id)).to be(false)
  end

  it 'nao enxerga assistente de outra conta' do
    outro = create(:captain_assistant, account: create(:account))

    get "/api/v1/accounts/#{account.id}/captain/assistants/#{outro.id}/ia_casos", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end
end
