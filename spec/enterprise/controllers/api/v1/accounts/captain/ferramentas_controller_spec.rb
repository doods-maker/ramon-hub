require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::Ferramentas', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:captain_assistant, account: account, name: 'Atendimento') }
  let(:url) { "/api/v1/accounts/#{account.id}/captain/ferramentas" }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  def registrar(tool_name, status:, quando:)
    Captain::ToolRun.create!(account_id: account.id, tool_name: tool_name, status: status, params: {},
                             resultado: 'ok', duration_ms: 5, created_at: quando)
  end

  it 'lista o catalogo com sistema, as skills ativas que usam e as execucoes de 7 dias' do
    skill = create(:captain_scenario, assistant: assistant, account: account, title: 'Lead aceitou a reuniao',
                                      instruction: 'Combinada a data, use [Mover](tool://mover_etapa).')
    create(:captain_scenario, assistant: assistant, account: account, enabled: false,
                              instruction: 'Use [Mover](tool://mover_etapa).')
    registrar('mover_etapa', status: 'erro', quando: 2.days.ago)
    registrar('mover_etapa', status: 'ok', quando: 1.hour.ago)
    registrar('mover_etapa', status: 'erro', quando: 10.days.ago)

    get url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    mover = json_response[:payload].find { |tool| tool[:id] == 'mover_etapa' }
    expect(mover).to include(nivel: 'sugestao', sistema: 'funil', execucoes_7d: 2, erros_7d: 1)
    expect(mover[:skills]).to eq([{ id: skill.id, title: 'Lead aceitou a reuniao', assistant_id: assistant.id,
                                    assistant_name: 'Atendimento' }])
    expect(Time.zone.parse(mover[:ultima_execucao_em])).to be_within(1.minute).of(1.hour.ago)
  end

  it 'ferramenta que nunca rodou nem e usada vem zerada' do
    get url, headers: agent.create_new_auth_token, as: :json

    faq = json_response[:payload].find { |tool| tool[:id] == 'faq_lookup' }
    expect(faq).to include(skills: [], ultima_execucao_em: nil, execucoes_7d: 0, erros_7d: 0)
  end

  it 'exige autenticacao' do
    get url, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
