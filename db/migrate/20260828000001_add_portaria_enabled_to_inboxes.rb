class AddPortariaEnabledToInboxes < ActiveRecord::Migration[7.1]
  def change
    add_column :inboxes, :portaria_enabled, :boolean, null: false, default: false
  end
end
