require 'rails_helper'

RSpec.describe 'Ramon Conteudo API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:peca) { create(:peca, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/ramon_conteudo" }

  it 'agente não acessa' do
    get base, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'lista as peças (sem reprovadas)' do
    create(:peca, account: account, status: 'reprovado')
    get base, headers: admin.create_new_auth_token
    expect(response.parsed_body['payload'].pluck('id')).to eq [peca.id]
  end

  it 'aprova a pauta' do
    post "#{base}/#{peca.id}/aprovar", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(peca.reload.status).to eq 'aprovado'
  end

  it 'reprova com nota' do
    post "#{base}/#{peca.id}/reprovar", params: { nota: 'tema repetido' }, headers: admin.create_new_auth_token
    expect(peca.reload).to have_attributes(status: 'reprovado', nota_reprovacao: 'tema repetido')
  end

  it '409 quando o status mudou por baixo' do
    peca.update_columns(status: 'montando')
    post "#{base}/#{peca.id}/aprovar", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:conflict)
    expect(peca.reload.status).to eq 'montando'
  end

  it 'edita a legenda de peça pronta' do
    peca.update_columns(status: 'montado')
    patch "#{base}/#{peca.id}/atualizar_legenda", params: { legenda: 'nova' }, headers: admin.create_new_auth_token
    expect(peca.reload.legenda).to eq 'nova'
  end

  it 'não edita legenda de peça publicada' do
    peca.update_columns(status: 'publicado')
    patch "#{base}/#{peca.id}/atualizar_legenda", params: { legenda: 'nova' }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:conflict)
  end

  it 'pede refação dos cards escolhidos' do
    peca.update_columns(status: 'montado')
    post "#{base}/#{peca.id}/refazer", params: { cards: [2, 9, 'x'] }, headers: admin.create_new_auth_token
    expect(peca.reload).to have_attributes(status: 'montado', refazer_cards: [2])
  end
end
