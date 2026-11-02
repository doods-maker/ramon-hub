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

  describe 'admin que não participa só lê' do
    it 'não envia', :aggregate_failures do
      mandar(admin, ana_bia)

      expect(response).to have_http_status(:forbidden)
      expect(ana_bia.messages.count).to eq(0)
    end

    it 'não aparece digitando' do
      url = "#{base}/conversations/#{ana_bia.display_id}/toggle_typing_status"
      post url, params: { typing_status: 'on' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'continua lendo' do
      expect(ids_na_caixa(admin)).to include(ana_bia.display_id)
    end

    it 'admin que participa do Geral envia' do
      mandar(admin, geral)

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'apagar' do
    def mensagem_de(user, conversation)
      create(:message, account: account, inbox: inbox, conversation: conversation, sender: user, message_type: :outgoing, content: 'oi')
    end

    def apagar(user, message)
      delete "#{base}/conversations/#{message.conversation.display_id}/messages/#{message.id}",
             headers: user.create_new_auth_token, as: :json
    end

    it 'colega não apaga mensagem alheia', :aggregate_failures do
      msg = mensagem_de(ana, ana_bia)
      apagar(bia, msg)

      expect(response).to have_http_status(:forbidden)
      expect(msg.reload.content).to eq('oi')
    end

    it 'autor apaga a própria', :aggregate_failures do
      msg = mensagem_de(ana, ana_bia)
      apagar(ana, msg)

      expect(response).to have_http_status(:ok)
      expect(msg.reload.content_attributes['deleted']).to be(true)
    end

    it 'admin que participa apaga no Geral' do
      apagar(admin, mensagem_de(ana, geral))

      expect(response).to have_http_status(:ok)
    end

    it 'admin de fora não apaga' do
      apagar(admin, mensagem_de(ana, ana_bia))

      expect(response).to have_http_status(:forbidden)
    end

    it 'caixa de cliente não muda: agente apaga mensagem de outro numa caixa comum', :aggregate_failures do
      comum = create(:inbox, account: account)
      create(:inbox_member, inbox: comum, user: bia)
      conversa = create(:conversation, account: account, inbox: comum)
      msg = create(:message, account: account, inbox: comum, conversation: conversa, sender: ana, message_type: :outgoing)
      apagar(bia, msg)

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'dados da conversa' do
    it 'expõe tipo e pessoas', :aggregate_failures do
      get "#{base}/conversations/#{ana_bia.display_id}", headers: ana.create_new_auth_token, as: :json
      expect(response.parsed_body['equipe_tipo']).to eq('1a1')
      expect(response.parsed_body['equipe_pessoas'].pluck('id')).to contain_exactly(ana.id, bia.id)

      get "#{base}/conversations/#{geral.display_id}", headers: ana.create_new_auth_token, as: :json
      expect(response.parsed_body).to include('equipe_tipo' => 'grupo', 'equipe_pessoas' => [])
    end
  end

  describe 'portas laterais' do
    it 'a API pública de caixa Api não abre a Equipe (source_id previsível)' do
      get "/public/api/v1/inboxes/#{inbox.channel.identifier}/contacts/equipe-1a1-#{ana.id}-#{bia.id}/conversations"

      expect(response).to have_http_status(:not_found)
    end

    it 'abrir o painel do lead numa conversa da Equipe não cria lead' do
      post "#{base}/leads/for_conversation", params: { conversation_id: geral.display_id }, headers: admin.create_new_auth_token, as: :json

      expect(account.leads.count).to eq(0)
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
