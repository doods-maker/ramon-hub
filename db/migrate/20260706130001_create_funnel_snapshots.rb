class CreateFunnelSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :funnel_snapshots do |t|
      t.references :account, null: false, index: false
      t.date :snapshot_date, null: false
      t.references :lead_stage, null: true, foreign_key: { on_delete: :nullify }
      t.string :stage_name, null: false
      t.integer :stage_position, null: false, default: 0
      t.boolean :is_won, null: false, default: false
      t.boolean :is_lost, null: false, default: false
      t.references :thesis, null: true, foreign_key: { on_delete: :nullify }
      t.string :thesis_name
      t.integer :leads_count, null: false, default: 0
      t.decimal :value_sum, precision: 14, scale: 2, null: false, default: 0
      t.timestamps
    end
    add_index :funnel_snapshots, [:account_id, :snapshot_date]
  end
end
