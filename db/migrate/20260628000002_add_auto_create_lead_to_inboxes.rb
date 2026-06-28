class AddAutoCreateLeadToInboxes < ActiveRecord::Migration[7.1]
  def change
    add_column :inboxes, :auto_create_lead, :boolean, null: false, default: false
  end
end
