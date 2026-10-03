require 'rails_helper'

RSpec.describe 'Ramon Extrato API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:sdr) { create(:user, account: account, role: :agent) }
  let(:closer) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_extrato" }

  before do
    create(:team_member, team: create(:team, account: account, name: 'sdr'), user: sdr)
    create(:team_member, team: create(:team, account: account, name: 'closer'), user: closer)
  end

  it 'gestor vê o extrato de todo mundo no mês pedido', :aggregate_failures do
    get url, params: { mes: '2026-11' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['mes']).to eq('2026-11')
    expect(response.parsed_body['pessoas'].map { |p| p['user']['id'] }).to contain_exactly(sdr.id, closer.id)
  end

  it 'agente vê só o próprio extrato' do
    get url, params: { mes: '2026-11' }, headers: sdr.create_new_auth_token, as: :json

    expect(response.parsed_body['pessoas'].map { |p| p['user']['id'] }).to eq([sdr.id])
  end

  it 'gestor lança a meta do mês (cria e atualiza)', :aggregate_failures do
    put "#{url}/meta", params: { mes: '2026-11', user_id: sdr.id, papel: 'sdr', meta: 25, rampa: true },
                       headers: admin.create_new_auth_token, as: :json
    put "#{url}/meta", params: { mes: '2026-11', user_id: sdr.id, papel: 'sdr', meta: 30, rampa: true },
                       headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(MetaComercial.where(user: sdr).pluck(:mes, :meta, :rampa)).to eq([[Date.new(2026, 11, 1), 30, true]])
  end

  it 'agente não lança meta' do
    put "#{url}/meta", params: { mes: '2026-11', user_id: sdr.id, papel: 'sdr', meta: 999 },
                       headers: sdr.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
