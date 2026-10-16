require 'rails_helper'

RSpec.describe 'Funil Ações API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:novo) { account.lead_stages.find_by(label: 'fase-novo') }
  let(:lead) { create(:lead, account: account, lead_stage: account.lead_stages.find_by(label: 'fase-qualificacao')) }
  let(:acao) do
    FunilAcao.create!(account: account, lead: lead, peca: 'etapa_ia', acao: 'mover_etapa', alvo: 'Qualificação',
                      ensaio: false, desfazer: { 'etapa_id' => novo.id })
  end

  def desfazer(alvo_lead, alvo_acao, headers: agent.create_new_auth_token)
    post "/api/v1/accounts/#{account.id}/leads/#{alvo_lead.id}/funil_acoes/#{alvo_acao.id}/desfazer", headers: headers, as: :json
  end

  it 'desfaz a ação e devolve o lead completo (200)', :aggregate_failures do
    desfazer(lead, acao)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('id' => lead.id, 'lead_stage_id' => novo.id)
    expect(response.parsed_body).to have_key('custom_attributes')
    expect(response.parsed_body['funil_acao']).to be_nil
    expect(acao.reload.desfeita_por).to eq(agent)
  end

  it 'desfazer de novo dá 422' do
    desfazer(lead, acao)
    desfazer(lead, acao)

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'lead de outra conta dá 404' do
    estranho = create(:lead)
    outra = FunilAcao.create!(account: estranho.account, lead: estranho, peca: 'etapa_ia', acao: 'mover_etapa', ensaio: false)
    desfazer(estranho, outra)

    expect(response).to have_http_status(:not_found)
  end

  it 'sem autenticação dá 401' do
    post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/funil_acoes/#{acao.id}/desfazer", as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'o índice do Kanban traz o chip da última ação viva' do
    acao
    get "/api/v1/accounts/#{account.id}/leads", headers: agent.create_new_auth_token, as: :json

    chip = response.parsed_body['payload'].find { |l| l['id'] == lead.id }['funil_acao']
    expect(chip).to eq('id' => acao.id, 'texto' => 'mover etapa → Qualificação')
  end
end
