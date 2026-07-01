class CreateLeadActivities < ActiveRecord::Migration[7.1]
  def change
    create_table :lead_activities do |t|
      t.references :account, null: false, foreign_key: true
      t.references :lead, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string :kind, null: false
      t.string :from_value
      t.string :to_value
      t.datetime :created_at, null: false
    end
    add_index :lead_activities, [:lead_id, :created_at]
  end
end
