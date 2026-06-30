class AddA1FieldsToLeadsAndStages < ActiveRecord::Migration[7.1]
  def change
    add_column :leads, :value, :decimal, precision: 12, scale: 2, null: true
    add_column :leads, :source, :string, null: true
    add_column :leads, :notes, :text, null: true
    add_column :lead_stages, :color, :string, null: true
  end
end
