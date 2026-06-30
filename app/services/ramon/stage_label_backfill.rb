# frozen_string_literal: true

module Ramon
  # Aplica, uma vez, a label fase-* da etapa atual em cada lead que já tem conversa.
  class StageLabelBackfill
    def self.perform
      Account.find_each { |account| new(account).perform }
    end

    def initialize(account)
      @account = account
    end

    def perform
      @account.leads.where.not(conversation_id: nil).find_each do |lead|
        Ramon::StageLabelSync.apply_to_conversation(lead)
      end
    end
  end
end
