require 'rails_helper'

describe Messages::MentionService do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let!(:first_agent) { create(:user, account: account) }
  let!(:second_agent) { create(:user, account: account) }
  let!(:third_agent) { create(:user, account: account) }
  let!(:admin_user) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: user) }
  let!(:team) { create(:team, account: account, name: 'Support Team') }
  let!(:empty_team) { create(:team, account: account, name: 'Empty Team') }
  let(:builder) { double }

  before do
    create(:inbox_member, user: first_agent, inbox: inbox)
    create(:inbox_member, user: second_agent, inbox: inbox)
    create(:team_member, user: first_agent, team: team)
    create(:team_member, user: second_agent, team: team)
    conversation.reload
    allow(NotificationBuilder).to receive(:new).and_return(builder)
    allow(builder).to receive(:perform)
    allow(Conversations::UserMentionJob).to receive(:perform_later)
  end

  describe '#perform' do
    context 'when message is not private' do
      it 'does not process mentions for public messages' do
        message = build(
          :message,
          conversation: conversation,
          account: account,
          content: "hi (mention://user/#{first_agent.id}/#{first_agent.name})",
          private: false
        )

        described_class.new(message: message).perform

        expect(NotificationBuilder).not_to have_received(:new)
        expect(Conversations::UserMentionJob).not_to have_received(:perform_later)
      end
    end

    context 'when message has no content' do
      it 'does not process mentions for empty messages' do
        message = build(
          :message,
          conversation: conversation,
          account: account,
          content: nil,
          private: true
        )

        described_class.new(message: message).perform

        expect(NotificationBuilder).not_to have_received(:new)
        expect(Conversations::UserMentionJob).not_to have_received(:perform_later)
      end
    end

    context 'when message has no mentions' do
      it 'does not process messages without mentions' do
        message = build(
          :message,
          conversation: conversation,
          account: account,
          content: 'just a regular message',
          private: true
        )

        described_class.new(message: message).perform

        expect(NotificationBuilder).not_to have_received(:new)
        expect(Conversations::UserMentionJob).not_to have_received(:perform_later)
      end
    end
  end

  describe 'user mentions' do
    context 'when message contains single user mention' do
      it 'creates notifications for inbox member who was mentioned' do
        message = build(
          :message,
          conversation: conversation,
          account: account,
          content: "hi (mention://user/#{first_agent.id}/#{first_agent.name})",
          private: true
        )

        described_class.new(message: message).perform

        expect(NotificationBuilder).to have_received(:new).with(
          notification_type: 'conversation_mention',
          user: first_agent,
          account: account,
          primary_actor: message.conversation,
          secondary_actor: message
        )
        expect(Conversations::UserMentionJob).to have_received(:perform_later).with(
          [first_agent.id.to_s],
          conversation.id,
          account.id
        )
      end

      it 'adds mentioned user as conversation participant' do
        message = build(
          :message,
          conversation: conversation,
          account: account,
          content: "hi (mention://user/#{first_agent.id}/#{first_agent.name})",
          private: true
        )

        described_class.new(message: message).perform

        expect(conversation.conversation_participants.map(&:user_id)).to include(first_agent.id)
      end

      it 'adds the mentioned user as a participant before generating the notification' do
        message = build(
          :message,
          conversation: conversation,
          account: account,
          content: "hi (mention://user/#{first_agent.id}/#{first_agent.name})",
          private: true
        )

        participant_user_ids_when_notified = nil
        allow(NotificationBuilder).to receive(:new) do |**_kwargs|
          participant_user_ids_when_notified = conversation.conversation_participants.reload.map(&:user_id)
          builder
        end

        described_class.new(message: message).perform

        expect(participant_user_ids_when_notified).to include(first_agent.id)
      end
    end

    context 'when message contains multiple user mentions' do
      let(:message) do
        build(
          :message,
          conversation: conversation,
          account: account,
          content: "hey (mention://user/#{second_agent.id}/#{second_agent.name}) " \
                   "and (mention://user/#{first_agent.id}/#{first_agent.name}), please look into this?",
          private: true
        )
      end

      it 'creates notifications for all mentioned inbox members' do
        described_class.new(message: message).perform

        expect(NotificationBuilder).to have_received(:new).with(
          notification_type: 'conversation_mention',
          user: second_agent,
          account: account,
          primary_actor: message.conversation,
          secondary_actor: message
        )
        expect(NotificationBuilder).to have_received(:new).with(
          notification_type: 'conversation_mention',
          user: first_agent,
          account: account,
          primary_actor: message.conversation,
          secondary_actor: message
        )
      end

      it 'adds all mentioned users to the participants list' do
        described_class.new(message: message).perform
        expect(conversation.conversation_participants.map(&:user_id)).to contain_exactly(first_agent.id, second_agent.id)
      end

      it 'passes unique user IDs to UserMentionJob' do
        described_class.new(message: message).perform
        expect(Conversations::UserMentionJob).to have_received(:perform_later).with(
          contain_exactly(first_agent.id.to_s, second_agent.id.to_s),
          conversation.id,
          account.id
        )
      end
    end

    context 'when the message sender mentions themselves' do
      it 'skips the sender notification while notifying other mentioned users' do
        message = build(
          :message,
          conversation: conversation,
          account: account,
          content: "hey (mention://user/#{first_agent.id}/#{first_agent.name}) and (mention://user/#{second_agent.id}/#{second_agent.name})",
          private: true,
          sender: first_agent
        )

        described_class.new(message: message).perform

        expect(NotificationBuilder).not_to have_received(:new).with(
          notification_type: 'conversation_mention',
          user: first_agent,
          account: account,
          primary_actor: message.conversation,
          secondary_actor: message
        )
        expect(NotificationBuilder).to have_received(:new).with(
          notification_type: 'conversation_mention',
          user: second_agent,
          account: account,
          primary_actor: message.conversation,
          secondary_actor: message
        )
      end
    end

    context 'when mentioned user is not an inbox member' do
      let!(:non_member_user) { create(:user, account: account) }

      it 'does not create notifications for non-inbox members' do
        message = build(
          :message,
          conversation: conversation,
          account: account,
          content: "hi (mention://user/#{non_member_user.id}/#{non_member_user.name})",
          private: true
        )

        described_class.new(message: message).perform

        expect(NotificationBuilder).not_to have_received(:new)
        expect(Conversations::UserMentionJob).not_to have_received(:perform_later)
      end
    end

    context 'when mentioned user is an admin' do
      it 'creates notifications for admin users even if not inbox members' do
        message = build(
          :message,
          conversation: conversation,
          account: account,
          content: "hi (mention://user/#{admin_user.id}/#{admin_user.name})",
          private: true
        )

        described_class.new(message: message).perform

        expect(NotificationBuilder).to have_received(:new).with(
          notification_type: 'conversation_mention',
          user: admin_user,
          account: account,
          primary_actor: message.conversation,
          secondary_actor: message
        )
      end
    end

    context 'when same user is mentioned multiple times' do
      it 'creates only one notification per user' do
        message = build(
          :message,
          conversation: conversation,
          account: account,
          content: "hi (mention://user/#{first_agent.id}/#{first_agent.name}) and again (mention://user/#{first_agent.id}/#{first_agent.name})",
          private: true
        )

        described_class.new(message: message).perform

        expect(NotificationBuilder).to have_received(:new).once
        expect(Conversations::UserMentionJob).to have_received(:perform_later).with(
          [first_agent.id.to_s],
          conversation.id,
          account.id
        )
      end
    end
  end

  describe 'team mentions' do
    context 'when message contains single team mention' do
      it 'creates notifications for all team members who are inbox members' do
        message = build(
          :message,
          conversation: conversation,
          account: account,
          content: "hey (mention://team/#{team.id}/#{team.name}) please help",
          private: true
        )

        described_class.new(message: message).perform

        expect(NotificationBuilder).to have_received(:new).with(
          notification_type: 'conversation_mention',
          user: first_agent,
          account: account,
          primary_actor: message.conversation,
          secondary_actor: message
        )
        expect(NotificationBuilder).to have_received(:new).with(
          notification_type: 'conversation_mention',
          user: second_agent,
          account: account,
          primary_actor: message.conversation,
          secondary_actor: message
        )
      end

      it 'adds all team members as conversation participants' do
        message = build(
          :message,
          conversation: conversation,
          account: account,
          content: "hey (mention://team/#{team.id}/#{team.name}) please help",
          private: true
        )

        described_class.new(message: message).perform

        expect(conversation.conversation_participants.map(&:user_id)).to contain_exactly(first_agent.id, second_agent.id)
      end

      it 'passes team member IDs to UserMentionJob' do
        message = build(
          :message,
          conversation: conversation,
          account: account,
          content: "hey (mention://team/#{team.id}/#{team.name}) please help",
          private: true
        )

        described_class.new(message: message).perform

        expect(Conversations::UserMentionJob).to have_received(:perform_later).with(
          contain_exactly(first_agent.id.to_s, second_agent.id.to_s),
          conversation.id,
          account.id
        )
      end
    end

    context 'when team has members who are not inbox members' do
      let!(:non_inbox_team_member) { create(:user, account: account) }

      before do
        create(:team_member, user: non_inbox_team_member, team: team)
      end

      it 'only notifies team members who are also inbox members' do
        message = build(
          :message,
          conversation: conversation,
          account: account,
          content: "hey (mention://team/#{team.id}/#{team.name}) please help",
          private: true
        )

        described_class.new(message: message).perform

        expect(NotificationBuilder).to have_received(:new).with(
          notification_type: 'conversation_mention', user: first_agent, account: account,
          primary_actor: message.conversation, secondary_actor: message
        )
        expect(NotificationBuilder).to have_received(:new).with(
          notification_type: 'conversation_mention', user: second_agent, account: account,
          primary_actor: message.conversation, secondary_actor: message
        )
        expect(NotificationBuilder).not_to have_received(:new).with(
          notification_type: 'conversation_mention', user: non_inbox_team_member, account: account,
          primary_actor: message.conversation, secondary_actor: message
        )
      end
    end

    context 'when team has admin members' do
      before do
        create(:team_member, user: admin_user, team: team)
      end

      it 'includes admin team members in notifications' do
        message = build(
          :message,
          conversation: conversation,
          account: account,
          content: "hey (mention://team/#{team.id}/#{team.name}) please help",
          private: true
        )

        described_class.new(message: message).perform

        expect(NotificationBuilder).to have_received(:new).with(
          notification_type: 'conversation_mention',
          user: admin_user,
          account: account,
          primary_actor: message.conversation,
          secondary_actor: message
        )
      end
    end

    context 'when team is empty' do
      it 'does not create any notifications for empty teams' do
        message = build(
          :message,
          conversation: conversation,
          account: account,
          content: "hey (mention://team/#{empty_team.id}/#{empty_team.name}) please help",
          private: true
        )

        described_class.new(message: message).perform

        expect(NotificationBuilder).not_to have_received(:new)
        expect(Conversations::UserMentionJob).not_to have_received(:perform_later)
      end
    end

    context 'when team does not exist' do
      it 'does not create notifications for non-existent teams' do
        message = build(
          :message,
          conversation: conversation,
          account: account,
          content: 'hey (mention://team/99999/NonExistentTeam) please help',
          private: true
        )

        described_class.new(message: message).perform

        expect(NotificationBuilder).not_to have_received(:new)
        expect(Conversations::UserMentionJob).not_to have_received(:perform_later)
      end
    end

    context 'when same team is mentioned multiple times' do
      it 'creates only one notification per team member' do
        message = build(
          :message,
          conversation: conversation,
          account: account,
          content: "hey (mention://team/#{team.id}/#{team.name}) and again (mention://team/#{team.id}/#{team.name})",
          private: true
        )

        described_class.new(message: message).perform

        expect(NotificationBuilder).to have_received(:new).exactly(2).times
        expect(Conversations::UserMentionJob).to have_received(:perform_later).with(
          contain_exactly(first_agent.id.to_s, second_agent.id.to_s),
          conversation.id,
          account.id
        )
      end
    end
  end

  describe 'mixed user and team mentions' do
    context 'when message contains both user and team mentions' do
      it 'creates notifications for both individual users and team members' do
        message = build(
          :message,
          conversation: conversation,
          account: account,
          content: "hey (mention://user/#{third_agent.id}/#{third_agent.name}) and (mention://team/#{team.id}/#{team.name})",
          private: true
        )

        # Make third_agent an inbox member
        create(:inbox_member, user: third_agent, inbox: inbox)

        described_class.new(message: message).perform

        expect(NotificationBuilder).to have_received(:new).with(
          notification_type: 'conversation_mention', user: third_agent, account: account,
          primary_actor: message.conversation, secondary_actor: message
        )
        expect(NotificationBuilder).to have_received(:new).with(
          notification_type: 'conversation_mention', user: first_agent, account: account,
          primary_actor: message.conversation, secondary_actor: message
        )
        expect(NotificationBuilder).to have_received(:new).with(
          notification_type: 'conversation_mention', user: second_agent, account: account,
          primary_actor: message.conversation, secondary_actor: message
        )
      end

      it 'avoids duplicate notifications when user is mentioned directly and via team' do
        message = build(
          :message,
          conversation: conversation,
          account: account,
          content: "hey (mention://user/#{first_agent.id}/#{first_agent.name}) and (mention://team/#{team.id}/#{team.name})",
          private: true
        )

        described_class.new(message: message).perform

        # first_agent should only receive one notification despite being mentioned directly and via team
        expect(NotificationBuilder).to have_received(:new).with(
          notification_type: 'conversation_mention',
          user: first_agent,
          account: account,
          primary_actor: message.conversation,
          secondary_actor: message
        ).once
        expect(NotificationBuilder).to have_received(:new).with(
          notification_type: 'conversation_mention',
          user: second_agent,
          account: account,
          primary_actor: message.conversation,
          secondary_actor: message
        ).once
      end
    end
  end

  # rubocop:disable RSpec/MultipleMemoizedHelpers
  describe 'na caixa Equipe' do
    let!(:ana) { create(:user, account: account) }
    let!(:bia) { create(:user, account: account) }
    let!(:caio) { create(:user, account: account) }
    let(:setor) { create(:team, account: account, name: 'Setor X') }
    let(:geral) { Ramon::Equipe.caixa(account).contact_inboxes.find_by!(source_id: 'equipe-geral').conversations.first }
    let(:no_setor) { Ramon::Equipe.caixa(account).contact_inboxes.find_by!(source_id: "equipe-time-#{setor.id}").conversations.first }

    before do
      allow(Rails.configuration.dispatcher).to receive(:dispatch)
      allow(NotificationBuilder).to receive(:new).and_call_original
      create(:team_member, team: setor, user: ana)
      create(:team_member, team: setor, user: bia)
      Ramon::Equipe.sincronizar(account, criar: true)
    end

    def escrever(conversa, texto, autor: ana, privada: false)
      create(:message, conversation: conversa, account: account, inbox: conversa.inbox, sender: autor,
                       message_type: :outgoing, content: texto, private: privada)
    end

    def avisar(message)
      described_class.new(message: message).perform
      Messages::NewMessageNotificationService.new(message: message).perform
    end

    def tipos(user) = Notification.where(user: user).pluck(:notification_type)

    it 'mensagem pública marca participante, com 1 notificação só', :aggregate_failures do
      avisar(escrever(no_setor, "oi [@bia](mention://user/#{bia.id}/bia)"))

      expect(tipos(bia)).to eq(['conversation_mention'])
      expect(Conversations::UserMentionJob).not_to have_received(:perform_later)
    end

    it 'id de quem não participa é ignorado e não vira participante', :aggregate_failures do
      avisar(escrever(no_setor, "oi (mention://user/#{caio.id}/caio)"))

      expect(tipos(caio)).to be_empty
      expect(no_setor.conversation_participants.pluck(:user_id)).not_to include(caio.id)
    end

    it 'admin de fora não é marcado' do
      admin_fora = create(:user, account: account, role: :administrator)
      no_setor.conversation_participants.where(user_id: admin_fora.id).destroy_all

      avisar(escrever(no_setor, "oi (mention://user/#{admin_fora.id}/adm)"))

      expect(tipos(admin_fora)).to be_empty
    end

    it '@todos marca todos menos quem escreveu', :aggregate_failures do
      avisar(escrever(geral, 'atenção [@todos](mention://todos/0/todos)'))

      expect(tipos(bia)).to eq(['conversation_mention'])
      expect(tipos(caio)).to eq(['conversation_mention'])
      expect(tipos(ana)).to be_empty
    end

    it '"@todos" em texto puro não marca (só aviso comum)' do
      avisar(escrever(geral, 'atenção @todos'))

      expect(tipos(bia)).to eq(['participating_conversation_new_message'])
    end

    it '@todos em 1:1 é ignorado' do
      ana_bia = Ramon::Equipe.conversa_1a1(account, ana, bia)

      avisar(escrever(ana_bia, '[@todos](mention://todos/0/todos)'))

      expect(Notification.where(notification_type: 'conversation_mention')).to be_empty
    end

    it 'caixa de cliente: mensagem pública com token continua sem efeito' do
      message = build(:message, conversation: conversation, account: account, private: false,
                                content: "hi (mention://user/#{first_agent.id}/x) [@todos](mention://todos/0/todos)")

      described_class.new(message: message).perform

      expect(NotificationBuilder).not_to have_received(:new)
    end
  end

  # rubocop:enable RSpec/MultipleMemoizedHelpers

  describe 'cross-account validation' do
    let!(:other_account) { create(:account) }
    let!(:other_team) { create(:team, account: other_account) }
    let!(:other_user) { create(:user, account: other_account) }

    before do
      create(:team_member, user: other_user, team: other_team)
    end

    it 'does not process mentions for teams from other accounts' do
      message = build(
        :message,
        conversation: conversation,
        account: account,
        content: "hey (mention://team/#{other_team.id}/#{other_team.name})",
        private: true
      )

      described_class.new(message: message).perform

      expect(NotificationBuilder).not_to have_received(:new)
      expect(Conversations::UserMentionJob).not_to have_received(:perform_later)
    end

    it 'does not process mentions for users from other accounts' do
      message = build(
        :message,
        conversation: conversation,
        account: account,
        content: "hey (mention://user/#{other_user.id}/#{other_user.name})",
        private: true
      )

      described_class.new(message: message).perform

      expect(NotificationBuilder).not_to have_received(:new)
      expect(Conversations::UserMentionJob).not_to have_received(:perform_later)
    end
  end
end
