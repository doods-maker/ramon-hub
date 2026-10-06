require 'rails_helper'

RSpec.describe 'Ramon Painel do time API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:sdr) { create(:user, account: account, role: :agent) }
  let(:outro_sdr) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_painel_time" }

  before do
    time_sdr = create(:team, account: account, name: 'sdr')
    [sdr, outro_sdr].each { |user| create(:team_member, team: time_sdr, user: user) }
  end

  it 'gestor recebe o agregado do time e a lista por pessoa (padrão: SDR, mês)', :aggregate_failures do
    get url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body).to include('papel' => 'sdr', 'periodo' => 'mes')
    expect(body['time']['kpis'].keys).to include('primeira_resposta', 'sem_resposta', 'show', 'registro_completo')
    expect(body['pessoas'].map { |p| p['user']['id'] }).to contain_exactly(sdr.id, outro_sdr.id)
  end

  it 'agente recebe só a própria linha, sem o time' do
    get url, params: { papel: 'sdr', periodo: 'semana' }, headers: sdr.create_new_auth_token, as: :json

    expect(response.parsed_body.slice('time', 'periodo')).to eq('time' => nil, 'periodo' => 'semana')
    expect(response.parsed_body['pessoas'].map { |p| p['user']['id'] }).to eq([sdr.id])
  end

  it 'Closer devolve os KPIs do Closer com a meta do plano', :aggregate_failures do
    get url, params: { papel: 'closer', periodo: 'mes_passado' }, headers: admin.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body['time']['kpis'].keys).to contain_exactly('conversao', 'assinado_na_reuniao', 'docs_7d', 'cancelamento_7d',
                                                          'painel', 'dossie_24h', 'vou_pensar_48h')
    expect(body['metas']['cancelamento_7d']).to eq('alvo' => 5, 'sentido' => 'max', 'unidade' => '%')
    expect(body['pessoas']).to eq([])
  end

  it 'sem login dá 401' do
    get url, as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end
