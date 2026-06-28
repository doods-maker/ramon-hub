class CreateRamonLeads < ActiveRecord::Migration[7.1]
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def change
    create_table :lead_stages do |t|
      t.references :account, null: false, index: false
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.boolean :is_won, null: false, default: false
      t.boolean :is_lost, null: false, default: false
      t.timestamps
    end
    add_index :lead_stages, [:account_id, :name], unique: true

    create_table :benefit_types do |t|
      t.references :account, null: false, index: false
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :benefit_types, [:account_id, :name], unique: true

    create_table :lead_priorities do |t|
      t.references :account, null: false, index: false
      t.string :name, null: false
      t.integer :weight, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :lead_priorities, [:account_id, :name], unique: true

    create_table :leads do |t|
      t.references :account, null: false, index: true
      t.references :contact, null: true, index: true
      t.references :conversation, null: true, index: true
      t.references :lead_stage, null: false, index: true
      t.references :benefit_type, null: true, index: true
      t.references :lead_priority, null: true, index: true
      t.string :name
      t.float :position, null: false, default: 0
      t.bigint :sdr_id
      t.bigint :closer_id
      t.string :lost_reason
      t.jsonb :custom_attributes, null: false, default: {}
      t.timestamps
    end
    add_index :leads, [:account_id, :lead_stage_id]

    reversible do |dir|
      dir.up do
        Account.find_each { |account| Leads::SeedDefaultConfigService.new(account).perform }
      end
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
end
