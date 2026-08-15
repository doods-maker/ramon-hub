class AddLeadToRamonReunioes < ActiveRecord::Migration[7.1]
  def change
    add_reference :ramon_reunioes, :lead, foreign_key: true, index: true
  end
end
