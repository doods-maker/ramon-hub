class CreateLeadNotes < ActiveRecord::Migration[7.1]
  def change
    create_table :lead_notes do |t|
      t.references :account, null: false, foreign_key: true
      t.references :lead, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.text :body, null: false
      t.timestamps
    end
    add_index :lead_notes, [:lead_id, :created_at]
  end
end
