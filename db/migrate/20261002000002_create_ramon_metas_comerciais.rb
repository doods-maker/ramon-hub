# Meta individual do mês (Termo de Metas) — base do bônus e dos degraus do
# extrato da variável (regulamento §4-A). O gestor digita no hub.
class CreateRamonMetasComerciais < ActiveRecord::Migration[7.1]
  def change
    create_table :ramon_metas_comerciais do |t|
      t.references :account, null: false
      t.references :user, null: false
      t.string :papel, null: false
      t.date :mes, null: false
      t.integer :meta, null: false, default: 0
      t.boolean :rampa, null: false, default: false
      t.timestamps
    end
    add_index :ramon_metas_comerciais, [:account_id, :user_id, :mes], unique: true
  end
end
