class AddTokenUsageToLeadTriages < ActiveRecord::Migration[7.1]
  def change
    add_column :lead_triages, :input_tokens, :integer, default: 0, null: false
    add_column :lead_triages, :output_tokens, :integer, default: 0, null: false
  end
end
