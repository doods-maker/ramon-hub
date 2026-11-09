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

  it 'gestor lança a meta do mês com papel e fator (cria e atualiza)', :aggregate_failures do
    travel_to(Time.zone.parse('2026-11-15 12:00:00 UTC')) do
      put "#{url}/meta", params: { mes: '2026-11', user_id: sdr.id, papel: 'sdr', meta: 25 },
                         headers: admin.create_new_auth_token, as: :json
      put "#{url}/meta", params: { mes: '2026-11', user_id: closer.id, papel: 'hibrido', meta: 0 },
                         headers: admin.create_new_auth_token, as: :json
      put "#{url}/meta", params: { mes: '2026-11', user_id: sdr.id, papel: 'sdr', meta: 30, fator: 0.8 },
                         headers: admin.create_new_auth_token, as: :json
    end

    expect(response).to have_http_status(:success)
    expect(MetaComercial.where(user: sdr).pluck(:mes, :meta, :fator)).to eq([[Date.new(2026, 11, 1), 30, 0.8]])
    expect(MetaComercial.find_by(user: closer).papel).to eq('hibrido')
  end

  it 'gestor cria e edita o Programa de Metas; agente não vê', :aggregate_failures do
    regras = { faixas: [{ min: 25, valor: 300 }], gas: { acima_de: 40, valor: 25 } }
    travel_to(Time.zone.parse('2026-11-15 12:00:00 UTC')) do
      post "#{url}/programa", params: { inicio: '2026-12-01', fim: '2027-02-28', regras: regras },
                              headers: admin.create_new_auth_token, as: :json
      id = response.parsed_body['id']
      post "#{url}/programa", params: { id: id, inicio: '2026-12-01', fim: '2027-02-28', regras: regras.merge(faixas: [{ min: 30, valor: 300 }]) },
                              headers: admin.create_new_auth_token, as: :json

      get "#{url}/programas", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body.map { |p| p.dig('regras', 'faixas', 0, 'min') }).to eq([30])

      get "#{url}/programas", headers: sdr.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'agente não lança meta' do
    put "#{url}/meta", params: { mes: '2026-11', user_id: sdr.id, papel: 'sdr', meta: 999 },
                       headers: sdr.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'mês fechado (3º dia útil): devolve o extrato guardado e não aceita meta', :aggregate_failures do
    travel_to(Time.zone.parse('2026-12-10 12:00:00 UTC')) do
      put "#{url}/meta", params: { mes: '2026-11', user_id: sdr.id, papel: 'sdr', meta: 25 },
                         headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      get url, params: { mes: '2026-11' }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['pessoas'].pluck('fechado_em')).to all(be_present)
    end
  end
end
