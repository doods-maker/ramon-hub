class CreateCaptainToolRuns < ActiveRecord::Migration[7.1]
  def change
    create_table :captain_tool_runs do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :assistant_id
      t.bigint :conversation_id
      t.bigint :lead_id
      t.string :tool_name, null: false
      t.string :status, null: false, default: 'ok'
      t.integer :duration_ms
      t.jsonb :params, default: {}
      t.text :resultado
      t.datetime :created_at, null: false
    end
    add_index :captain_tool_runs, [:account_id, :created_at]
  end
end
