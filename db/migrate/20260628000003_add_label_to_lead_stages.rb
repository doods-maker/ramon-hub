class AddLabelToLeadStages < ActiveRecord::Migration[7.1]
  def up
    add_column :lead_stages, :label, :string
    add_index :lead_stages, [:account_id, :label], unique: true, name: 'index_lead_stages_on_account_id_and_label'

    # Backfill: grava labels nas etapas existentes e cria as Labels fase-*.
    # perform é idempotente (find_or_create + update do label).
    Account.find_each { |account| Leads::SeedDefaultConfigService.new(account).perform }
  end

  def down
    remove_index :lead_stages, name: 'index_lead_stages_on_account_id_and_label'
    remove_column :lead_stages, :label
  end
end
