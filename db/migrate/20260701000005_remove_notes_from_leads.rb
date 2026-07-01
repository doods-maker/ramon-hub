class RemoveNotesFromLeads < ActiveRecord::Migration[7.1]
  def change
    remove_column :leads, :notes, :text
  end
end
