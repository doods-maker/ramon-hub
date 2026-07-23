class CreateCopilotSuggestions < ActiveRecord::Migration[7.1]
  def change
    create_table :copilot_suggestions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :lead, null: false, foreign_key: true
      t.string :kind, null: false
      t.jsonb :payload, default: {}
      t.string :status, default: 'pending'
      t.datetime :run_at
      t.timestamps
    end
    add_index :copilot_suggestions, [:account_id, :status]
  end
end
