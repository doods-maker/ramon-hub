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

  def mensagem_de(user, conversation)
    create(:message, account: account, inbox: inbox, conversation: conversation, sender: user, message_type: :outgoing, content: 'oi')
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

  # Na Equipe só participantes + administradores veem, ponto (ADR 0011). Fora dela: specs de policy, filtro e listener.
  describe 'atribuição, time e membro de caixa não dão acesso' do
    def expect_de_fora(user)
      expect(ids_na_caixa(user)).not_to include(ana_bia.display_id)

      get "#{base}/conversations/#{ana_bia.display_id}", headers: user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it '1:1 atribuída a um colega de fora segue invisível para ele', :aggregate_failures do
      ana_bia.update!(assignee: caio)

      expect_de_fora(caio)
    end

    it '1:1 com o time de um colega de fora segue invisível para ele', :aggregate_failures do
      create(:team_member, team: advogados, user: caio)
      ana_bia.update!(team: advogados)

      expect_de_fora(caio)
    end

    it 'membro da caixa não passa a ver', :aggregate_failures do
      create(:inbox_member, inbox: inbox, user: caio)

      expect_de_fora(caio)
    end

    it 'admin de fora segue vendo', :aggregate_failures do
      ana_bia.update!(assignee: caio)

      expect(ids_na_caixa(admin)).to include(ana_bia.display_id)
      get "#{base}/conversations/#{ana_bia.display_id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
    end

    it 'participante segue vendo a 1:1 atribuída a outro' do
      ana_bia.update!(assignee: caio)

      expect(ids_na_caixa(ana)).to include(ana_bia.display_id)
    end
  end

  describe 'lista do que o HTTP aceita numa conversa da Equipe' do
    let(:msg) { mensagem_de(ana, ana_bia) }

    def chamar(user, verbo, caminho, corpo = {}, conversation: ana_bia)
      public_send(verbo, "#{base}/conversations/#{conversation.display_id}#{caminho}",
                  params: corpo, headers: user.create_new_auth_token, as: :json)
    end

    def recusadas
      [[:post, '/participants', { user_ids: [caio.id] }], [:patch, '/participants', { user_ids: [ana.id] }],
       [:delete, '/participants', { user_ids: [bia.id] }], [:post, '/assignments', { assignee_id: caio.id }],
       [:post, '/assignments', { team_id: advogados.id }], [:post, '/labels', { labels: ['x'] }],
       [:post, '/toggle_status', { status: 'resolved' }], [:post, '/toggle_priority', { priority: 'urgent' }],
       [:post, '/mute'], [:post, '/unmute'], [:post, '/unread'], [:post, '/custom_attributes', { custom_attributes: { a: 1 } }],
       [:patch, '', { priority: 'urgent' }], [:delete, ''], [:post, '/ramon_copilot', { mode: 'summary' }],
       [:patch, '/draft_messages', { draft_message: { message: 'x' } }],
       [:patch, "/messages/#{msg.id}", { status: 'read' }], [:post, "/messages/#{msg.id}/translate", { target_language: 'en' }]]
    end

    it 'admin de fora e participante recebem 403 no que é de atendimento, e nada muda', :aggregate_failures do
      expect(Ramon::ConversationCopilotService).not_to receive(:new)

      [admin, ana].each do |user|
        recusadas.each do |verbo, caminho, corpo|
          chamar(user, verbo, caminho, corpo || {})
          expect(response).to have_http_status(:forbidden), "#{verbo} #{caminho}: #{response.status}"
        end
      end

      ana_bia.reload
      expect(ana_bia).to have_attributes(status: 'open', assignee_id: nil, team_id: nil, priority: nil)
      expect(ana_bia.conversation_participants.pluck(:user_id)).to contain_exactly(ana.id, bia.id)
      expect(ana_bia.label_list).to be_empty
      expect(msg.reload.status).to eq('sent')
    end

    # A ação só existe com enterprise: sem ela, a rota dá 404 antes de qualquer before_action (o CI remove enterprise).
    it 'inbox_assistant fica fora da lista' do
      expect(Ramon::Equipe.http_permitido?(ana_bia, 'api/v1/accounts/conversations', 'inbox_assistant')).to be(false)
    end

    it 'transcript: 403 para admin de fora e participante, sem mandar a conversa por e-mail', :aggregate_failures do
      expect(ConversationReplyMailer).not_to receive(:with)

      [admin, ana].each do |user|
        chamar(user, :post, '/transcript', { email: 'fora@example.com' })
        expect(response).to have_http_status(:forbidden)
      end
    end

    it 'participante abre, lê, digita, marca lida, envia e apaga a própria', :aggregate_failures do
      [[:get, ''], [:get, '/messages'], [:get, '/attachments'], [:get, '/labels'], [:get, '/participants'], [:post, '/update_last_seen'],
       [:post, '/toggle_typing_status', { typing_status: 'on' }], [:post, '/messages', { content: 'oi' }],
       [:delete, "/messages/#{msg.id}"]].each do |verbo, caminho, corpo|
        chamar(ana, verbo, caminho, corpo || {})
        expect(response).to have_http_status(:success), "#{verbo} #{caminho}: #{response.status}"
      end
      expect(msg.reload.content_attributes['deleted']).to be(true)
    end

    it 'admin de fora segue lendo', :aggregate_failures do
      [[:get, ''], [:get, '/messages'], [:get, '/attachments'], [:get, '/labels'], [:get, '/participants']].each do |verbo, caminho|
        chamar(admin, verbo, caminho)
        expect(response).to have_http_status(:success), "#{verbo} #{caminho}: #{response.status}"
      end
    end

    it 'caixa comum não muda', :aggregate_failures do
      conversa = create(:conversation, account: account, inbox: create(:inbox, account: account))

      [[:post, '/assignments', { assignee_id: admin.id }], [:post, '/toggle_status', { status: 'resolved' }],
       [:post, '/participants', { user_ids: [ana.id] }], [:post, '/labels', { labels: ['x'] }], [:post, '/mute'],
       [:post, '/custom_attributes', { custom_attributes: { a: 1 } }]].each do |verbo, caminho, corpo|
        chamar(admin, verbo, caminho, corpo || {}, conversation: conversa)
        expect(response).to have_http_status(:success), "#{verbo} #{caminho}: #{response.status}"
      end
    end

    it 'macro que inclui conversa da Equipe: 403, sem enfileirar', :aggregate_failures do
      macro = create(:macro, account: account, created_by: admin, updated_by: admin, visibility: :global)
      comum = create(:conversation, account: account, inbox: create(:inbox, account: account))

      expect do
        post "#{base}/macros/#{macro.id}/execute", params: { conversation_ids: [comum.display_id, ana_bia.display_id] },
                                                   headers: admin.create_new_auth_token, as: :json
      end.not_to have_enqueued_job(MacrosExecutionJob)
      expect(response).to have_http_status(:forbidden)
    end

    it 'ação em massa que inclui conversa da Equipe: 403, sem enfileirar', :aggregate_failures do
      expect do
        post "#{base}/bulk_actions", params: { type: 'Conversation', ids: [ana_bia.display_id], fields: { status: 'resolved' } },
                                     headers: ana.create_new_auth_token, as: :json
      end.not_to have_enqueued_job(BulkActionsJob)
      expect(response).to have_http_status(:forbidden)
    end

    it 'não cria conversa na caixa Equipe pela API', :aggregate_failures do
      contato = create(:contact, account: account)

      post "#{base}/conversations", params: { inbox_id: inbox.id, contact_id: contato.id, source_id: 'qualquer' },
                                    headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(contato.conversations).to be_empty
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

  describe 'GET /ramon_equipe/participantes' do
    def participantes_de(user, conversation)
      get "#{base}/ramon_equipe/participantes", params: { conversation_id: conversation.display_id },
                                                headers: user.create_new_auth_token, as: :json
    end

    it 'participante e admin veem quem está na conversa, com last_seen_at em segundos', :aggregate_failures do
      ana_bia.conversation_participants.find_by(user: bia).update!(last_seen_at: Time.zone.at(1_700_000_000))
      ana_bia.conversation_participants.find_by(user: ana).update!(last_seen_at: nil)

      [ana, admin].each do |user|
        participantes_de(user, ana_bia)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.pluck('id')).to contain_exactly(ana.id, bia.id)
        expect(response.parsed_body.find { |p| p['id'] == bia.id }).to include('last_seen_at' => 1_700_000_000, 'name' => bia.available_name)
        expect(response.parsed_body.find { |p| p['id'] == ana.id }['last_seen_at']).to be_nil
      end
    end

    it 'colega de fora não vê a 1:1 alheia' do
      participantes_de(caio, ana_bia)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'conversa de fora da Equipe é 404', :aggregate_failures do
      comum = create(:inbox, account: account)
      conversa = create(:conversation, account: account, inbox: comum)
      participantes_de(admin, conversa)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /ramon_equipe/reacao' do
    let(:msg) { mensagem_de(ana, ana_bia) }

    def reagir(user, message, emoji, conversation: message.conversation)
      post "#{base}/ramon_equipe/reacao", params: { conversation_id: conversation.display_id, message_id: message.id, emoji: emoji },
                                          headers: user.create_new_auth_token, as: :json
    end

    def reacoes(message) = message.reload.content_attributes['ramon_reacoes']

    it 'emoji novo soma, outro troca, o mesmo tira', :aggregate_failures do
      reagir(bia, msg, '👍')
      expect(response).to have_http_status(:ok)
      expect(reacoes(msg)).to eq([{ 'user_id' => bia.id, 'user_name' => bia.available_name, 'emoji' => '👍' }])

      reagir(bia, msg, '❤️')
      expect(reacoes(msg).pluck('emoji')).to eq(['❤️'])

      reagir(bia, msg, '❤️')
      expect(reacoes(msg)).to eq([])
    end

    it 'duas pessoas reagem sem se apagar', :aggregate_failures do
      reagir(ana, msg, '👍')
      reagir(bia, msg, '👍')

      expect(reacoes(msg).pluck('user_id')).to contain_exactly(ana.id, bia.id)
      expect(reacoes(msg).pluck('emoji')).to eq(%w[👍 👍])
    end

    it 'preserva as outras chaves de content_attributes e não mexe no conteúdo', :aggregate_failures do
      citada = mensagem_de(bia, ana_bia)
      msg.update!(content_attributes: { in_reply_to: citada.id })
      reagir(bia, msg, '🙏')

      expect(msg.reload.content_attributes['in_reply_to']).to eq(citada.id)
      expect(msg.content).to eq('oi')
      expect(reacoes(msg).pluck('emoji')).to eq(['🙏'])
    end

    it 'emoji fora da lista: 422', :aggregate_failures do
      reagir(bia, msg, '🔥')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(reacoes(msg)).to be_nil
    end

    it 'quem não participa: 403, inclusive admin', :aggregate_failures do
      [admin, caio].each do |user|
        reagir(user, msg, '👍')
        expect(response).to have_http_status(:forbidden)
      end
      expect(reacoes(msg)).to be_nil
    end

    it 'admin que participa reage' do
      reagir(admin, mensagem_de(ana, geral), '👍')

      expect(response).to have_http_status(:ok)
    end

    it 'mensagem apagada: 422', :aggregate_failures do
      msg.update!(content_attributes: { deleted: true })
      reagir(bia, msg, '👍')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(reacoes(msg)).to be_nil
    end

    it 'conversa fora da Equipe: 404' do
      comum = create(:inbox, account: account)
      conversa = create(:conversation, account: account, inbox: comum)
      reagir(admin, create(:message, account: account, inbox: comum, conversation: conversa), '👍')

      expect(response).to have_http_status(:not_found)
    end

    it 'mensagem de outra conversa: 404', :aggregate_failures do
      reagir(bia, mensagem_de(ana, geral), '👍', conversation: ana_bia)

      expect(response).to have_http_status(:not_found)
      expect(geral.messages.last.content_attributes['ramon_reacoes']).to be_nil
    end

    it 'não gera notificação nem altera last_activity_at nem a não-lida', :aggregate_failures do
      msg
      atividade = ana_bia.reload.last_activity_at

      expect { perform_enqueued_jobs { reagir(bia, msg, '👍') } }.not_to change(Notification, :count)

      expect(response).to have_http_status(:ok)
      expect(ana_bia.reload.last_activity_at).to eq(atividade)
      expect(Ramon::Equipe.nao_lidas(ana_bia, bia)).to eq(1)
      expect(Ramon::Equipe.nao_lidas(ana_bia, ana)).to eq(0)
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
