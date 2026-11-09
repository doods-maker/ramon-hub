require 'rails_helper'

RSpec.describe Api::V1::Accounts::LeadAptoController, type: :request do
  let(:account) { create(:account) }
  let(:won_stage) { account.lead_stages.find_by(is_won: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:advogada) { create(:user, account: account, role: :agent) }
  let(:outra) { create(:user, account: account, role: :agent) }
  let(:closer) { create(:user, account: account, role: :agent) }
  let(:tese) { create(:thesis, account: account, name: 'Tese do endpoint', validador_ids: [advogada.id]) }
  let(:lead) do
    create(:lead, account: account, lead_stage: won_stage, thesis: tese, closer: closer).tap do |l|
      l.update_columns(contrato_limpo_em: 1.day.ago, validacao_desde: 1.day.ago) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  before do
    admin
    # advogadas veem o cliente já ganho; os demais entram pelo time de visão total
    create(:team_member, team: create(:team, account: account, name: 'closer'), user: closer)
    create(:team_member, team: create(:team, account: account, name: 'comercial'), user: outra)
  end

  def apto(user, **params)
    post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/apto", params: params, headers: user.create_new_auth_token, as: :json
  end

  it 'a advogada da tese valida e recebe o lead com a situação nova', :aggregate_failures do
    apto(advogada, acao: 'validar')

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('apto_situacao' => 'apto', 'apto_prazo' => nil)
    expect(lead.reload.apto_por_id).to eq(advogada.id)
  end

  it 'quem vê o lead mas não é da tese leva 403' do
    apto(outra, acao: 'validar')

    expect(response).to have_http_status(:forbidden)
  end

  it 'devolver sem motivo é 422; com motivo devolve', :aggregate_failures do
    apto(advogada, acao: 'devolver', motivo: '')
    expect(response).to have_http_status(:unprocessable_entity)

    apto(advogada, acao: 'devolver', motivo: 'Falta o laudo')
    expect(response.parsed_body).to include('apto_situacao' => 'devolvido', 'devolvido_motivo' => 'Falta o laudo')
  end

  it 'o Closer reenvia o devolvido; só o admin designa', :aggregate_failures do
    apto(advogada, acao: 'devolver', motivo: 'Falta o laudo')
    apto(closer, acao: 'reenviar')
    expect(response.parsed_body).to include('apto_situacao' => 'aguardando')

    apto(closer, acao: 'designar', user_id: outra.id)
    expect(response).to have_http_status(:forbidden)

    apto(admin, acao: 'designar', user_id: outra.id)
    expect(response.parsed_body).to include('validador_id' => outra.id)

    apto(admin, acao: 'designar', user_id: 0)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(lead.reload.validador_id).to eq(outra.id)
  end
end
