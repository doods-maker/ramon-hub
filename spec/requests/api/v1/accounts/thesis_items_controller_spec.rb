require 'rails_helper'

RSpec.describe 'Thesis Items API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:thesis) { account.theses.create!(name: 'Tese de Teste', position: 50) }

  describe 'POST create' do
    it 'cria o item posicionando no fim da tese (admin)' do
      thesis.thesis_items.create!(section: 'abertura', content: 'Existente', position: 0)
      post "/api/v1/accounts/#{account.id}/theses/#{thesis.id}/thesis_items",
           params: { section: 'objecao', title: 'Item', content: 'Conteúdo' },
           headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['position']).to eq(1)
      expect(body['thesis_id']).to eq(thesis.id)
    end

    it 'barra agente (admin-only)' do
      post "/api/v1/accounts/#{account.id}/theses/#{thesis.id}/thesis_items",
           params: { section: 'abertura', content: 'X' }, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH update' do
    it 'atualiza o item (admin)' do
      item = thesis.thesis_items.create!(section: 'abertura', content: 'Velho', position: 0)
      patch "/api/v1/accounts/#{account.id}/theses/#{thesis.id}/thesis_items/#{item.id}",
            params: { content: 'Novo' }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(item.reload.content).to eq('Novo')
    end

    it 'barra agente (admin-only)' do
      item = thesis.thesis_items.create!(section: 'abertura', content: 'Velho', position: 0)
      patch "/api/v1/accounts/#{account.id}/theses/#{thesis.id}/thesis_items/#{item.id}",
            params: { content: 'Novo' }, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'DELETE destroy' do
    it 'remove o item (admin)' do
      item = thesis.thesis_items.create!(section: 'abertura', content: 'X', position: 0)
      delete "/api/v1/accounts/#{account.id}/theses/#{thesis.id}/thesis_items/#{item.id}",
             headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(thesis.thesis_items.exists?(item.id)).to be(false)
    end
  end

  describe 'POST reorder' do
    it 'persiste a ordem pelas posições, escopada à tese (admin)' do
      a = thesis.thesis_items.create!(section: 'abertura', content: 'A', position: 0)
      b = thesis.thesis_items.create!(section: 'abertura', content: 'B', position: 1)
      post "/api/v1/accounts/#{account.id}/theses/#{thesis.id}/thesis_items/reorder",
           params: { ids: [b.id, a.id] }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(b.reload.position).to eq(0)
      expect(a.reload.position).to eq(1)
    end

    it 'barra agente (admin-only)' do
      post "/api/v1/accounts/#{account.id}/theses/#{thesis.id}/thesis_items/reorder",
           params: { ids: [] }, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
