# Pastas do Drive que a esteira deixou prontas (marcador _pasta-pronta.json): lista por advogado + sino.
class CreateRamonPastasProntas < ActiveRecord::Migration[7.1]
  def change
    create_table :ramon_pastas_prontas do |t|
      t.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :drive_pasta_id, null: false
      t.string :titulo
      t.references :responsavel, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :ramon_pastas_prontas, %i[account_id drive_pasta_id], unique: true, name: 'index_ramon_pastas_prontas_on_conta_e_pasta'
  end
end
