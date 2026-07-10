class AddCnisToLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :leads, :cnis, :jsonb
  end
end
