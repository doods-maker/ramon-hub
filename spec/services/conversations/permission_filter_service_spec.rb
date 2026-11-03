require 'rails_helper'

RSpec.describe Conversations::PermissionFilterService do
  let(:account) { create(:account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:another_conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:inbox) { create(:inbox, account: account) }

  # This inbox_member is used to establish the agent's access to the inbox
  before { create(:inbox_member, user: agent, inbox: inbox) }

  describe '#perform' do
    context 'when user is an administrator' do
      it 'returns all conversations' do
        result = described_class.new(
          account.conversations,
          admin,
          account
        ).perform

        expect(result).to include(conversation)
        expect(result).to include(another_conversation)
        expect(result.count).to eq(2)
      end
    end

    context 'when user is an agent' do
      it 'returns all conversations with no further filtering' do
        inbox_ids = agent.inboxes.where(account_id: account.id).pluck(:id)

        # The base implementation returns all conversations
        # expecting the caller to filter by assigned inboxes
        result = described_class.new(
          account.conversations.where(inbox_id: inbox_ids),
          agent,
          account
        ).perform

        expect(result).to include(conversation)
        expect(result).to include(another_conversation)
        expect(result.count).to eq(2)
      end
    end

    # ramon: caixa do escritório — quem não é membro vê só o que é dele ou do time dele (ADR 0004)
    context 'when the agent is not a member of the inbox' do
      let(:office) { create(:inbox, account: account) }
      let(:lawyer) { create(:user, account: account, role: :agent) }
      let(:team) { create(:team, account: account) }
      let!(:assigned) { create(:conversation, account: account, inbox: office, assignee: lawyer) }
      let!(:of_team) { create(:conversation, account: account, inbox: office, team: team) }
      let!(:other) { create(:conversation, account: account, inbox: office) }

      it 'returns only conversations assigned to the agent or to their teams' do
        create(:team_member, team: team, user: lawyer)

        result = described_class.new(account.conversations, lawyer, account).perform

        expect(result).to contain_exactly(assigned, of_team)
        expect(result).not_to include(other)
      end
    end

    # ramon: na caixa Equipe só participantes + administradores (ADR 0011)
    context 'when the conversation is in the Equipe inbox' do
      let(:ana) { create(:user, account: account, role: :agent) }
      let(:bia) { create(:user, account: account, role: :agent) }
      let(:team) { create(:team, account: account) }
      let!(:par) do
        Ramon::Equipe.sincronizar(account, criar: true)
        Ramon::Equipe.conversa_1a1(account, ana, bia)
      end

      def visiveis(user) = described_class.new(account.conversations, user, account).perform

      it 'keeps out the assignee, the team member and the inbox member', :aggregate_failures do
        create(:team_member, team: team, user: agent)
        par.update!(team: team, assignee: agent)
        create(:inbox_member, inbox: par.inbox, user: agent)

        expect(visiveis(agent)).not_to include(par)
        expect(visiveis(agent)).to include(conversation, another_conversation)
      end

      it 'shows it to participants and administrators', :aggregate_failures do
        expect(visiveis(ana)).to include(par)
        expect(visiveis(admin)).to include(par)
      end

      it 'keeps assignment and team access in the other inboxes', :aggregate_failures do
        comum = create(:conversation, account: account, inbox: create(:inbox, account: account), assignee: ana)
        do_time = create(:conversation, account: account, inbox: comum.inbox, team: team)
        create(:team_member, team: team, user: ana)

        expect(visiveis(ana)).to include(comum, do_time)
      end
    end
  end
end
