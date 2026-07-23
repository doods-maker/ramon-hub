class AddFirstResponseSlaMinutesToInboxes < ActiveRecord::Migration[7.1]
  def change
    add_column :inboxes, :first_response_sla_minutes, :integer
  end
end
