require 'rails_helper'

RSpec.describe 'Lead Stages API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  # A conta recém-criada já vem semeada (Leads::SeedDefaultConfigService no
  # after_create), o que colide com os nomes/posições fixados abaixo. Limpamos
  # para cada exemplo partir de um funil vazio.
  before { account.lead_stages.destroy_all }

  describe 'POST create' do
    it 'cria a etapa derivando a etiqueta e posicionando no fim' do
      account.lead_stages.create!(name: 'Novo', position: 0)
      post "/api/v1/accounts/#{account.id}/lead_stages",
           params: { name: 'Proposta enviada', color: '#abcabc' },
           headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['label']).to eq('fase-proposta-enviada')
      expect(body['position']).to eq(1)
    end

    it 'barra agente (admin-only)' do
      post "/api/v1/accounts/#{account.id}/lead_stages",
           params: { name: 'X' }, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'DELETE destroy' do
    it 'move os leads para a etapa destino e remove a etapa' do
      origem = account.lead_stages.create!(name: 'Origem', position: 0)
      destino = account.lead_stages.create!(name: 'Destino', position: 1)
      lead = account.leads.create!(name: 'L', lead_stage: origem)

      delete "/api/v1/accounts/#{account.id}/lead_stages/#{origem.id}",
             params: { move_to_stage_id: destino.id },
             headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(account.lead_stages.exists?(origem.id)).to be(false)
      expect(lead.reload.lead_stage_id).to eq(destino.id)
    end

    it 'recusa sem destino válido' do
      s = account.lead_stages.create!(name: 'S', position: 0)
      account.lead_stages.create!(name: 'T', position: 1)
      account.leads.create!(name: 'L', lead_stage: s)
      delete "/api/v1/accounts/#{account.id}/lead_stages/#{s.id}",
             headers: admin.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'POST reorder' do
    it 'persiste a ordem pelas posições' do
      a = account.lead_stages.create!(name: 'A', position: 0)
      b = account.lead_stages.create!(name: 'B', position: 1)
      post "/api/v1/accounts/#{account.id}/lead_stages/reorder",
           params: { ids: [b.id, a.id] }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(b.reload.position).to eq(0)
      expect(a.reload.position).to eq(1)
    end
  end
end
