require 'rails_helper'

RSpec.describe Captain::Tools::Copilot::GetConversationService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:service) { described_class.new(assistant, user: user) }

  describe '#name' do
    it 'returns the correct service name' do
      expect(service.name).to eq('get_conversation')
    end
  end

  describe '#description' do
    it 'returns the service description' do
      expect(service.description).to eq('Get details of a conversation including messages and contact information')
    end
  end

  describe '#parameters' do
    it 'defines conversation_id parameter' do
      expect(service.parameters.keys).to contain_exactly(:conversation_id)
    end
  end

  describe '#active?' do
    context 'when user is an admin' do
      let(:user) { create(:user, :administrator, account: account) }
      let(:assistant) { create(:captain_assistant, account: account) }

      it 'returns true' do
        expect(service.active?).to be true
      end
    end

    context 'when user has custom role with conversation_manage permission' do
      let(:user) { create(:user, account: account) }
      let(:assistant) { create(:captain_assistant, account: account) }
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_manage']) }

      before do
        account_user = AccountUser.find_by(user: user, account: account)
        account_user.update(role: :agent, custom_role: custom_role)
      end

      it 'returns true' do
        expect(service.active?).to be true
      end
    end

    context 'when user has custom role with conversation_unassigned_manage permission' do
      let(:user) { create(:user, account: account) }
      let(:assistant) { create(:captain_assistant, account: account) }
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_unassigned_manage']) }

      before do
        account_user = AccountUser.find_by(user: user, account: account)
        account_user.update(role: :agent, custom_role: custom_role)
      end

      it 'returns true' do
        expect(service.active?).to be true
      end
    end

    context 'when user has custom role with conversation_participating_manage permission' do
      let(:user) { create(:user, account: account) }
      let(:assistant) { create(:captain_assistant, account: account) }
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_participating_manage']) }

      before do
        account_user = AccountUser.find_by(user: user, account: account)
        account_user.update(role: :agent, custom_role: custom_role)
      end

      it 'returns true' do
        expect(service.active?).to be true
      end
    end

    context 'when user has custom role without any conversation permissions' do
      let(:user) { create(:user, account: account) }
      let(:assistant) { create(:captain_assistant, account: account) }
      let(:custom_role) { create(:custom_role, account: account, permissions: []) }

      before do
        account_user = AccountUser.find_by(user: user, account: account)
        account_user.update(role: :agent, custom_role: custom_role)
      end

      it 'returns false' do
        expect(service.active?).to be false
      end
    end
  end

  describe '#execute' do
    context 'when conversation is not found' do
      it 'returns not found message' do
        expect(service.execute(conversation_id: 999)).to eq('Conversation not found')
      end
    end

    # ramon: conversa da Equipe nunca vai para a IA (ADR 0011)
    context 'when the conversation is in the Equipe inbox' do
      it 'answers as not found, even with a message inside' do
        AccountUser.find_by(user: user, account: account).update!(role: :administrator) # admin passa pelo filtro; só o fora_da_caixa barra
        Ramon::Equipe.sincronizar(account, criar: true)
        geral = Ramon::Equipe.caixa(account).contact_inboxes.find_by!(source_id: 'equipe-geral').conversations.first
        create(:message, account: account, inbox: geral.inbox, conversation: geral, sender: user, message_type: :outgoing, content: 'sigilo')

        expect(service.execute(conversation_id: geral.display_id)).to eq('Conversation not found')
      end
    end

    # ramon: agente só lê o que está no escopo dele (caixa de que é membro, atribuição ou time — ADR 0004)
    context 'when the agent has no access to the conversation' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_participating_manage']) }
      let(:other_agent) { create(:user, account: account) }
      let(:conversation) { create(:conversation, account: account, inbox: create(:inbox, account: account), assignee: other_agent) }

      before { AccountUser.find_by(user: user, account: account).update(role: :agent, custom_role: custom_role) }

      it 'answers as not found' do
        create(:message, conversation: conversation, message_type: 'outgoing', content: 'Nota sigilosa', private: true)

        expect(service.execute(conversation_id: conversation.display_id)).to eq('Conversation not found')
      end

      it 'returns the conversation when it is assigned to the agent' do
        conversation.update!(assignee: user)

        expect(service.execute(conversation_id: conversation.display_id)).to eq(conversation.to_llm_text)
      end
    end

    # ramon: caminho principal do ADR 0004, sem custom role — agente puro, fila do time e admin
    context 'when a plain agent asks for a conversation outside their inboxes' do
      let(:conversation) { create(:conversation, account: account, inbox: create(:inbox, account: account)) }

      it 'answers as not found' do
        expect(service.execute(conversation_id: conversation.display_id)).to eq('Conversation not found')
      end

      it 'returns the conversation when it is in the queue of one of their teams' do
        team = create(:team, account: account)
        create(:team_member, team: team, user: user)
        conversation.update!(team: team)

        expect(service.execute(conversation_id: conversation.display_id)).to eq(conversation.to_llm_text)
      end

      it 'returns it to an administrator' do
        AccountUser.find_by(user: user, account: account).update!(role: :administrator)

        expect(service.execute(conversation_id: conversation.display_id)).to eq(conversation.to_llm_text)
      end
    end

    context 'when conversation exists' do
      let(:inbox) { create(:inbox, account: account) }
      let(:conversation) { create(:conversation, account: account, inbox: inbox) }

      before { create(:inbox_member, user: user, inbox: inbox) }

      it 'returns the conversation in llm text format' do
        result = service.execute(conversation_id: conversation.display_id)
        expect(result).to eq(conversation.to_llm_text)
      end

      it 'includes private messages in the llm text format' do
        # Create a regular message
        create(:message,
               conversation: conversation,
               message_type: 'outgoing',
               content: 'Regular message',
               private: false)

        # Create a private message
        create(:message,
               conversation: conversation,
               message_type: 'outgoing',
               content: 'Private note content',
               private: true)

        result = service.execute(conversation_id: conversation.display_id)

        # Verify that the result includes both regular and private messages
        expect(result).to include('Regular message')
        expect(result).to include('Private note content')
        expect(result).to include('[Private Note]')
      end

      context 'when conversation belongs to different account' do
        let(:other_account) { create(:account) }
        let(:other_inbox) { create(:inbox, account: other_account) }
        let(:other_conversation) { create(:conversation, account: other_account, inbox: other_inbox) }

        it 'returns not found message' do
          expect(service.execute(conversation_id: other_conversation.display_id)).to eq('Conversation not found')
        end
      end
    end
  end
end
