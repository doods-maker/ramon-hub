class AddPrescriptionFieldsToLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :leads, :dcb_em, :date
    add_column :leads, :benefit_monthly_value, :decimal, precision: 12, scale: 2
  end
end
