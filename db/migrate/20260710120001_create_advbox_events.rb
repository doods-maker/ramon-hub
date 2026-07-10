class CreateAdvboxEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :advbox_events do |t|
      t.references :account, null: false
      t.string :event_key, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false, default: 'received'
      t.string :note
      t.timestamps
    end
    add_index :advbox_events, [:account_id, :event_key], unique: true
  end
end
