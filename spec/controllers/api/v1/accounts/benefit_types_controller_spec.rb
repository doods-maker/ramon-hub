require 'rails_helper'

RSpec.describe 'Benefit Types API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  # A conta recém-criada já vem semeada (after_create), colidindo com as
  # posições fixadas abaixo. Limpamos para partir de uma lista vazia.
  before { account.benefit_types.destroy_all }

  it 'cria posicionando no fim' do
    account.benefit_types.create!(name: 'A', position: 0)
    post "/api/v1/accounts/#{account.id}/benefit_types",
         params: { name: 'Revisão' }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['position']).to eq(1)
  end

  it 'reordena' do
    a = account.benefit_types.create!(name: 'A', position: 0)
    b = account.benefit_types.create!(name: 'B', position: 1)
    post "/api/v1/accounts/#{account.id}/benefit_types/reorder",
         params: { ids: [b.id, a.id] }, headers: admin.create_new_auth_token
    expect(b.reload.position).to eq(0)
  end

  it 'remove' do
    b = account.benefit_types.create!(name: 'X', position: 0)
    delete "/api/v1/accounts/#{account.id}/benefit_types/#{b.id}", headers: admin.create_new_auth_token
    expect(account.benefit_types.exists?(b.id)).to be(false)
  end
end
