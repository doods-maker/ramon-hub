require 'rails_helper'

RSpec.describe 'Theses API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  # A conta recém-criada já vem semeada com as 5 teses nativas do playbook
  # (Leads::SeedDefaultConfigService), então os testes usam nomes que não
  # colidem com o seed e levam em conta essa contagem inicial.
  describe 'GET index' do
    it 'lista as teses da conta (agent pode ler)' do
      get "/api/v1/accounts/#{account.id}/theses", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(response.parsed_body.size).to eq(5)
    end
  end

  describe 'GET show' do
    it 'inclui os itens ordenados da tese (agent pode ler)' do
      thesis = account.theses.create!(name: 'Tese Show', position: 50)
      thesis.thesis_items.create!(section: 'abertura', content: 'B', position: 1)
      thesis.thesis_items.create!(section: 'abertura', content: 'A', position: 0)

      get "/api/v1/accounts/#{account.id}/theses/#{thesis.id}", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['name']).to eq('Tese Show')
      expect(body['items'].map { |i| i['content'] }).to eq(%w[A B])
    end
  end

  describe 'POST create' do
    it 'cria a tese posicionando no fim (admin)' do
      post "/api/v1/accounts/#{account.id}/theses",
           params: { name: 'Tese Nova', area: 'previdenciario' },
           headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['position']).to eq(6)
    end

    it 'barra agente (admin-only)' do
      post "/api/v1/accounts/#{account.id}/theses",
           params: { name: 'X' }, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH update' do
    it 'atualiza a tese (admin)' do
      thesis = account.theses.create!(name: 'Tese Antiga', position: 50)
      patch "/api/v1/accounts/#{account.id}/theses/#{thesis.id}",
            params: { name: 'Tese Renomeada' },
            headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(thesis.reload.name).to eq('Tese Renomeada')
    end

    it 'barra agente (admin-only)' do
      thesis = account.theses.create!(name: 'Tese Antiga', position: 50)
      patch "/api/v1/accounts/#{account.id}/theses/#{thesis.id}",
            params: { name: 'X' }, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'DELETE destroy' do
    it 'remove a tese e anula thesis_id nos leads vinculados (admin)' do
      thesis = account.theses.create!(name: 'Tese Removida', position: 50)
      lead = account.leads.create!(name: 'L', lead_stage: account.lead_stages.first, thesis: thesis)

      delete "/api/v1/accounts/#{account.id}/theses/#{thesis.id}", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(account.theses.exists?(thesis.id)).to be(false)
      expect(lead.reload.thesis_id).to be_nil
    end
  end

  describe 'POST reorder' do
    it 'persiste a ordem pelas posições (admin)' do
      a = account.theses.create!(name: 'Tese A', position: 50)
      b = account.theses.create!(name: 'Tese B', position: 51)
      post "/api/v1/accounts/#{account.id}/theses/reorder",
           params: { ids: [b.id, a.id] }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(b.reload.position).to eq(0)
    end

    it 'barra agente (admin-only)' do
      post "/api/v1/accounts/#{account.id}/theses/reorder",
           params: { ids: [] }, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
