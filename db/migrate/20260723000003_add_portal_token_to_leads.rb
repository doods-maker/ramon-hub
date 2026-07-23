class AddPortalTokenToLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :leads, :portal_token, :string
    add_index :leads, :portal_token, unique: true
  end
end
