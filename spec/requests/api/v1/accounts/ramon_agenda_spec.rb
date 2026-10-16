require 'rails_helper'

RSpec.describe 'Ramon Agenda Google API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:bia) { create(:user, account: account, role: :agent, name: 'Bia') }
  let(:fora) { create(:user, account: account, role: :agent, name: 'Fora') }
  let(:base) { "/api/v1/accounts/#{account.id}/ramon_agenda/google" }
  let(:periodo) { { from: '2026-10-19T00:00:00-03:00', to: '2026-10-25T23:59:59-03:00' } }

  def cliente_com(itens)
    instance_double(Ramon::GoogleAgenda::Cliente, eventos: itens)
  end

  def evento(titulo, hub_task_id: nil, cancelado: false)
    { id: "e-#{titulo}", inicio: Time.zone.parse('2026-10-20 10:00'), fim: Time.zone.parse('2026-10-20 11:00'),
      titulo: titulo, cancelado: cancelado, hub_task_id: hub_task_id }
  end

  before do
    create(:team_member, team: create(:team, account: account, name: 'sdr'), user: ana)
    create(:team_member, team: create(:team, account: account, name: 'closer'), user: bia)
    [ana, bia, fora].each { |u| GoogleAgendaConta.create!(user: u, account: account, email: "#{u.name}@x.com", status: 'conectada') }
    allow(Ramon::GoogleAgenda::Cliente).to receive(:new) { |conta| cliente_com([evento("Compromisso #{conta.user.name}")]) }
  end

  it 'exige autenticacao' do
    get base, params: periodo, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'devolve 403 para quem nao e admin nem do comercial' do
    get base, params: periodo, headers: fora.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'membro do comercial recebe os compromissos de todos os membros e a lista de membros' do
    get base, params: periodo, headers: ana.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body['payload'].pluck('titulo')).to contain_exactly('Compromisso Ana', 'Compromisso Bia')
    expect(body['membros'].pluck('id')).to contain_exactly(ana.id, bia.id)
  end

  it 'filtra por pessoa e ignora ids fora do comercial' do
    get base, params: periodo.merge(user_ids: [bia.id, fora.id]), headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].pluck('user_id')).to eq([bia.id])
  end

  it 'deixa de fora eventos do hub e cancelados' do
    allow(Ramon::GoogleAgenda::Cliente).to receive(:new)
      .and_return(cliente_com([evento('Do hub', hub_task_id: 7), evento('Cancelado', cancelado: true), evento('Livre')]))
    get base, params: periodo.merge(user_ids: [ana.id]), headers: ana.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].pluck('titulo')).to eq(['Livre'])
  end

  it 'erro do Google numa pessoa nao derruba as outras' do
    allow(Ramon::GoogleAgenda::Cliente).to receive(:new) do |conta|
      raise Ramon::GoogleAgenda::Cliente::Erro, 500 if conta.user_id == ana.id

      cliente_com([evento('Da Bia')])
    end
    get base, params: periodo, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].pluck('titulo')).to eq(['Da Bia'])
    expect(response.parsed_body['erros']).to eq([ana.id])
  end

  it 'periodo invalido devolve 422' do
    get base, params: { from: 'x', to: 'y' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
