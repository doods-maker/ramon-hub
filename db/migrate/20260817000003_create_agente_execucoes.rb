class CreateAgenteExecucoes < ActiveRecord::Migration[7.1]
  def change
    create_table :agente_execucoes do |t|
      t.references :account, null: false, foreign_key: true
      t.references :conversation, foreign_key: true
      t.references :lead, foreign_key: true
      t.text :pedido, null: false
      t.string :status, null: false
      t.text :resumo
      t.jsonb :acoes, null: false, default: []
      t.string :modelo
      t.string :esforco
      t.integer :duracao_ms
      t.timestamps
    end
    add_index :agente_execucoes, [:account_id, :created_at]
  end
end
