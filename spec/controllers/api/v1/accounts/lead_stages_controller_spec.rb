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

    it 'não colide com o label fixo de uma etapa renomeada' do
      account.lead_stages.create!(name: 'Proposta antiga', label: 'fase-proposta', position: 0)
      post "/api/v1/accounts/#{account.id}/lead_stages",
           params: { name: 'Proposta' }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['label']).to eq('fase-proposta-2')
    end
  end

  describe 'PATCH update' do
    it 'renomeia só o nome exibido: o label fica fixo', :aggregate_failures do
      stage = account.lead_stages.create!(name: 'Reunião agendada', label: 'fase-reuniao-agendada', position: 0)
      patch "/api/v1/accounts/#{account.id}/lead_stages/#{stage.id}",
            params: { name: 'Reunião marcada' }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(stage.reload.name).to eq('Reunião marcada')
      expect(stage.label).to eq('fase-reuniao-agendada')
    end

    it 'salva o nome para o cliente', :aggregate_failures do
      stage = account.lead_stages.create!(name: 'Negociação', position: 0)
      patch "/api/v1/accounts/#{account.id}/lead_stages/#{stage.id}",
            params: { nome_cliente: 'Proposta em análise' }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['nome_cliente']).to eq('Proposta em análise')
    end
  end

  describe 'DELETE destroy' do
    it 'move os leads para a etapa destino e remove a etapa (via job)' do
      origem = account.lead_stages.create!(name: 'Origem', position: 0)
      destino = account.lead_stages.create!(name: 'Destino', position: 1)
      lead = account.leads.create!(name: 'L', lead_stage: origem)

      # only: sem o filtro, o Avatar job do contato tenta HTTP real (WebMock barra)
      perform_enqueued_jobs(only: Ramon::StageMergeJob) do
        delete "/api/v1/accounts/#{account.id}/lead_stages/#{origem.id}",
               params: { move_to_stage_id: destino.id },
               headers: admin.create_new_auth_token
      end

      expect(response).to have_http_status(:success)
      expect(account.lead_stages.exists?(origem.id)).to be(false)
      expect(lead.reload.lead_stage_id).to eq(destino.id)
    end

    it 'fundir no Perdido grava o motivo da fusão (o admin não escolhe um por lead)' do
      origem = account.lead_stages.create!(name: 'Origem', position: 0)
      perdido = account.lead_stages.create!(name: 'Perdido', position: 1, is_lost: true)
      lead = account.leads.create!(name: 'L', lead_stage: origem)
      perform_enqueued_jobs(only: Ramon::StageMergeJob) do
        delete "/api/v1/accounts/#{account.id}/lead_stages/#{origem.id}",
               params: { move_to_stage_id: perdido.id },
               headers: admin.create_new_auth_token
      end
      expect(lead.reload.lost_reason).to eq('Etapa Origem removida')
    end

    it 'responde na hora e deixa a movimentação pro job' do
      origem = account.lead_stages.create!(name: 'Origem', position: 0)
      destino = account.lead_stages.create!(name: 'Destino', position: 1)
      lead = account.leads.create!(name: 'L', lead_stage: origem)

      delete "/api/v1/accounts/#{account.id}/lead_stages/#{origem.id}",
             params: { move_to_stage_id: destino.id },
             headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(Ramon::StageMergeJob).to have_been_enqueued.with(origem.id, destino.id, admin.id)
      expect(lead.reload.lead_stage_id).to eq(origem.id)
    end

    it 'recusa remover etapa usada pelas automações' do
      protegida = account.lead_stages.create!(name: 'Qualificação', label: 'fase-qualificacao', position: 0)
      destino = account.lead_stages.create!(name: 'Destino', position: 1)
      delete "/api/v1/accounts/#{account.id}/lead_stages/#{protegida.id}",
             params: { move_to_stage_id: destino.id },
             headers: admin.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.lead_stages.exists?(protegida.id)).to be(true)
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
