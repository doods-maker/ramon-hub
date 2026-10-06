require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::IaRodadas', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/ia_rodadas" }
  let!(:caso) do
    Captain::IaCaso.create!(account: account, assistant: assistant, titulo: 'A1', mensagens: [{ role: 'user', content: 'oi' }])
  end

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  def rodada(**attrs)
    Captain::IaRodada.create!({ account: account, assistant: assistant, status: 'concluida' }.merge(attrs))
  end

  it 'agente nao roda' do
    post url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'admin enfileira a rodada com o total de casos ativos', :aggregate_failures do
    expect do
      post url, headers: admin.create_new_auth_token, as: :json
    end.to have_enqueued_job(Captain::IaRodadaJob)

    expect(response).to have_http_status(:success)
    expect(Captain::IaRodada.last).to have_attributes(status: 'fila', total: 1, disparado_por_id: admin.id)
    expect(json_response).not_to have_key(:resultados)
  end

  it 'uma rodada por assistente por vez', :aggregate_failures do
    rodada(status: 'rodando')

    expect { post url, headers: admin.create_new_auth_token, as: :json }.not_to have_enqueued_job(Captain::IaRodadaJob)
    expect(response).to have_http_status(:conflict)
  end

  it 'rodada travada ha muito tempo vira erro e libera o assistente', :aggregate_failures do
    travada = rodada(status: 'rodando')
    travada.update_columns(updated_at: 2.hours.ago) # rubocop:disable Rails/SkipsModelValidations

    post url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(travada.reload.status).to eq('erro')
  end

  it 'sem caso ativo nao roda' do
    caso.update!(ativo: false)

    post url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'lista o historico e o detalhe compara com a rodada anterior', :aggregate_failures do
    outro = Captain::IaCaso.create!(account: account, assistant: assistant, titulo: 'A2', mensagens: [{ role: 'user', content: 'oi' }])
    anterior = rodada(passou: 1, total: 2, resultados: [{ caso_id: caso.id, passou: true }, { caso_id: outro.id, passou: false }])
    atual = rodada(passou: 1, total: 2, resultados: [{ caso_id: caso.id, passou: false }, { caso_id: outro.id, passou: true }])

    get url, headers: admin.create_new_auth_token, as: :json
    expect(json_response[:payload].pluck(:id)).to eq([atual.id, anterior.id])

    get "#{url}/#{atual.id}", headers: admin.create_new_auth_token, as: :json
    expect(json_response[:resultados].size).to eq(2)
    expect(json_response[:comparacao]).to eq(rodada_id: anterior.id, passou: 1, total: 2, pioraram: [caso.id], melhoraram: [outro.id])
  end
end
