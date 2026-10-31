require 'rails_helper'

# Equipe · chat interno como caixa do Chatwoot (ADR 0011): cada um vê Geral, o canal dos times dele e as 1:1 dele;
# admin vê tudo; ninguém mais vê conversa alheia. Quem vê também responde; a não-lida é por pessoa.
RSpec.describe 'Ramon Equipe API', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:ana) { create(:user, account: account) }
  let!(:bia) { create(:user, account: account) }
  let!(:caio) { create(:user, account: account) }
  let!(:advogados) { create(:team, account: account, name: 'advogados') }
  let(:base) { "/api/v1/accounts/#{account.id}" }
  let(:inbox) { Ramon::Equipe.sincronizar(account, criar: true) }
  let(:geral) { inbox.contact_inboxes.find_by!(source_id: 'equipe-geral').conversations.first }
  let(:setor) { inbox.contact_inboxes.find_by!(source_id: "equipe-time-#{advogados.id}").conversations.first }
  let(:ana_bia) { Ramon::Equipe.conversa_1a1(account, ana, bia) }

  before do
    create(:team_member, team: advogados, user: ana)
    inbox
    ana_bia
  end

  def ids_na_caixa(user)
    get "#{base}/conversations", params: { inbox_id: inbox.id, assignee_type: 'all' }, headers: user.create_new_auth_token, as: :json
    response.parsed_body.dig('data', 'payload').pluck('id')
  end

  def mandar(user, conversation, content = 'oi')
    url = "#{base}/conversations/#{conversation.display_id}/messages"
    post url, params: { content: content }, headers: user.create_new_auth_token, as: :json
  end

  describe 'visibilidade' do
    it 'agente vê Geral, o canal do time dele e a 1:1 dele' do
      expect(ids_na_caixa(ana)).to contain_exactly(geral.display_id, setor.display_id, ana_bia.display_id)
    end

    it 'quem está fora não vê a 1:1 nem o canal do time alheio' do
      expect(ids_na_caixa(caio)).to contain_exactly(geral.display_id)

      get "#{base}/conversations/#{ana_bia.display_id}", headers: caio.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)

      mandar(caio, ana_bia)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'admin vê tudo, inclusive a 1:1 dos outros' do
      expect(ids_na_caixa(admin)).to contain_exactly(geral.display_id, setor.display_id, ana_bia.display_id)
    end

    it 'conversa da Equipe não aparece na lista geral de conversas' do
      get "#{base}/conversations", params: { assignee_type: 'all' }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body.dig('data', 'payload')).to be_empty
    end

    it 'sair do time tira o acesso ao canal do setor' do
      advogados.team_members.find_by(user: ana).destroy!

      expect(ids_na_caixa(ana)).not_to include(setor.display_id)
    end
  end

  describe 'responder e não-lida por pessoa' do
    it 'participante responde; a mensagem vira não-lida só de quem ainda não leu' do
      mandar(ana, ana_bia, 'bom dia')
      expect(response).to have_http_status(:success)

      get "#{base}/conversations/#{ana_bia.display_id}", headers: bia.create_new_auth_token, as: :json
      expect(response.parsed_body['unread_count']).to eq(1)

      post "#{base}/conversations/#{ana_bia.display_id}/update_last_seen", headers: bia.create_new_auth_token, as: :json
      get "#{base}/ramon_equipe", headers: bia.create_new_auth_token, as: :json
      expect(response.parsed_body).to include('inbox_id' => inbox.id, 'nao_lidas' => 0)
      expect(ana_bia.messages.last.sender).to eq(ana)
    end
  end

  describe 'POST /ramon_equipe/conversa' do
    it 'abre (ou reabre) a 1:1 com o colega' do
      post "#{base}/ramon_equipe/conversa", params: { user_id: bia.id }, headers: ana.create_new_auth_token, as: :json

      expect(response.parsed_body).to eq('id' => ana_bia.display_id)
    end

    it 'não abre 1:1 consigo mesmo nem com quem é de outra conta' do
      post "#{base}/ramon_equipe/conversa", params: { user_id: ana.id }, headers: ana.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      post "#{base}/ramon_equipe/conversa", params: { user_id: create(:user).id }, headers: ana.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
