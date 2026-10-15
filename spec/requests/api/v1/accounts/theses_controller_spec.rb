require 'rails_helper'

RSpec.describe 'Theses API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  # A conta recém-criada já vem semeada com as 11 teses nativas do playbook (5 previdenciárias + 4 trabalhistas + isenção de IR + salário-maternidade)
  # (Leads::SeedDefaultConfigService), então os testes usam nomes que não
  # colidem com o seed e levam em conta essa contagem inicial.
  describe 'GET index' do
    it 'lista as teses da conta (agent pode ler)' do
      get "/api/v1/accounts/#{account.id}/theses", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(response.parsed_body.size).to eq(11)
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

    it 'expõe os campos de honorário no show' do
      thesis = account.theses.create!(name: 'Tese Show Honorário', position: 51,
                                      honorario_percentual: 30, honorario_n_mensalidades: 3)
      get "/api/v1/accounts/#{account.id}/theses/#{thesis.id}", headers: agent.create_new_auth_token
      body = response.parsed_body
      expect(body['honorario_percentual'].to_f).to eq(30.0)
      expect(body['honorario_n_mensalidades']).to eq(3)
      expect(body).to include('honorario_na_tabela' => false, 'honorario_minimo_qtd' => nil)
    end
  end

  describe 'POST create' do
    it 'cria a tese posicionando no fim (admin)' do
      post "/api/v1/accounts/#{account.id}/theses",
           params: { name: 'Tese Nova', area: 'previdenciario' },
           headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['position']).to eq(12)
    end

    it 'nasce sem honorário e fora da tabela (JUR-02: alinhar com o Dr. Ramon)', :aggregate_failures do
      post "/api/v1/accounts/#{account.id}/theses",
           params: { name: 'Tese Padrão' }, headers: admin.create_new_auth_token
      body = response.parsed_body
      expect(body['honorario_percentual']).to be_nil
      expect(body['honorario_n_mensalidades']).to be_nil
      expect(body['honorario_na_tabela']).to be false
    end

    it 'respeita o honorário enviado na criação' do
      post "/api/v1/accounts/#{account.id}/theses",
           params: { name: 'Tese Própria', honorario_percentual: 25 }, headers: admin.create_new_auth_token
      expect(response.parsed_body['honorario_percentual'].to_f).to eq(25.0)
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

    it 'atualiza o honorário da tese (admin)' do
      thesis = account.theses.create!(name: 'Tese Honorário', position: 50)
      patch "/api/v1/accounts/#{account.id}/theses/#{thesis.id}",
            params: { honorario_percentual: 30, honorario_n_mensalidades: 3 },
            headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(thesis.reload.honorario_percentual).to eq(30)
      expect(thesis.reload.honorario_n_mensalidades).to eq(3)
    end

    it 'grava mínimo e tabela; mínimo vazio vira nil', :aggregate_failures do
      thesis = account.theses.create!(name: 'Tese Min', position: 60)
      patch "/api/v1/accounts/#{account.id}/theses/#{thesis.id}",
            params: { honorario_minimo_qtd: '3', honorario_minimo_base: 'sm', honorario_na_tabela: true },
            headers: admin.create_new_auth_token
      expect(response.parsed_body).to include('honorario_minimo_qtd' => 3, 'honorario_minimo_base' => 'sm',
                                              'honorario_na_tabela' => true)
      patch "/api/v1/accounts/#{account.id}/theses/#{thesis.id}",
            params: { honorario_minimo_qtd: '' }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(thesis.reload.honorario_minimo_qtd).to be_nil
    end
  end

  describe 'DELETE destroy' do
    it 'remove a tese sem leads (admin)' do
      thesis = account.theses.create!(name: 'Tese Removida', position: 50)

      delete "/api/v1/accounts/#{account.id}/theses/#{thesis.id}", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(account.theses.exists?(thesis.id)).to be(false)
    end

    it 'recusa remover tese usada por leads e devolve a contagem', :aggregate_failures do
      thesis = account.theses.create!(name: 'Tese Em Uso', position: 50)
      lead = account.leads.create!(name: 'L', lead_stage: account.lead_stages.first, thesis: thesis)

      delete "/api/v1/accounts/#{account.id}/theses/#{thesis.id}", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['leads_count']).to eq(1)
      expect(response.parsed_body['error']).to include('desative em vez de excluir')
      expect(account.theses.exists?(thesis.id)).to be(true)
      expect(lead.reload.thesis_id).to eq(thesis.id)
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

  describe 'palavras-chave (roteiro da tese, F2)' do
    it 'grava a lista, devolve no show e aceita lista vazia' do
      thesis = account.theses.create!(name: 'Tese Palavras', position: 60)
      patch "/api/v1/accounts/#{account.id}/theses/#{thesis.id}", params: { palavras_chave: %w[auxílio-acidente sequela] },
                                                                  headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['palavras_chave']).to eq(%w[auxílio-acidente sequela])

      patch "/api/v1/accounts/#{account.id}/theses/#{thesis.id}", params: { palavras_chave: [] },
                                                                  headers: admin.create_new_auth_token, as: :json
      expect(thesis.reload.palavras_chave).to eq([])
    end
  end

  describe 'modelo de contrato do ZapSign (roteiro F5)' do
    it 'grava, devolve no show e limpa com vazio' do
      thesis = account.theses.create!(name: 'Tese Modelo', position: 61)
      patch "/api/v1/accounts/#{account.id}/theses/#{thesis.id}", params: { zapsign_template_id: 'modelo-aa' },
                                                                  headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['zapsign_template_id']).to eq('modelo-aa')

      patch "/api/v1/accounts/#{account.id}/theses/#{thesis.id}", params: { zapsign_template_id: '' },
                                                                  headers: admin.create_new_auth_token, as: :json
      expect(thesis.reload.zapsign_template_id).to be_nil
    end
  end
end
