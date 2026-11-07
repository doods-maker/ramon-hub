require 'rails_helper'

# Etapa Documentos: o assistente é por conversa (Captain::AssistenteDaConversa) e escolhido uma vez por conversa no job.
# Captain é enterprise e o CI roda sem enterprise/: roda onde o Captain existe.
RSpec.describe 'Captain::InboxPendingConversationsResolutionJob, assistente por conversa', if: ChatwootApp.enterprise?, type: :job do
  let!(:inbox) { create(:inbox) }
  let!(:conversas) { create_list(:conversation, 2, inbox: inbox, last_activity_at: 2.hours.ago, status: :pending) }
  let!(:assistente) { create(:captain_assistant, account: inbox.account) }

  before { create(:captain_inbox, inbox: inbox, captain_assistant: assistente) }

  it 'escolhe o assistente uma vez por conversa e responde com ele', :aggregate_failures do
    allow(Captain::AssistenteDaConversa).to receive(:para).and_call_original

    Captain::InboxPendingConversationsResolutionJob.perform_now(inbox.reload)

    conversas.each do |conversa|
      expect(Captain::AssistenteDaConversa).to have_received(:para).with(conversa).once
      expect(conversa.reload.messages.where(sender: assistente)).to exist
    end
  end
end
