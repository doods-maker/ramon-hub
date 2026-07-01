class BackfillLeadCreatedActivities < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    Lead.find_each do |lead|
      next if LeadActivity.exists?(lead_id: lead.id, kind: 'created')

      LeadActivity.create!(account_id: lead.account_id, lead_id: lead.id,
                           kind: 'created', to_value: lead.source, created_at: lead.created_at)
    end
  end

  def down
    # rubocop:disable Rails/SkipsModelValidations
    LeadActivity.where(kind: 'created').delete_all
    # rubocop:enable Rails/SkipsModelValidations
  end
end
