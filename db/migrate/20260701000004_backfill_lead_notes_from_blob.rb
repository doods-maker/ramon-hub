class BackfillLeadNotesFromBlob < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    Lead.where.not(notes: [nil, '']).find_each do |lead|
      next if lead.lead_notes.exists?

      lead.lead_notes.create!(account_id: lead.account_id, body: lead.notes, created_at: lead.created_at)
    end
  end

  def down; end
end
