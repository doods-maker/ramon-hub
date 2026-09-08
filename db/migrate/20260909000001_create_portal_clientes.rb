class CreatePortalClientes < ActiveRecord::Migration[7.1]
  def change
    create_table :portal_clientes do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :advbox_customer_id, null: false
      t.string :nome, null: false
      t.string :cpf
      t.string :email, null: false
      t.string :codigo_digest
      t.datetime :codigo_expira_em
      t.datetime :convidado_em
      t.datetime :termos_aceitos_em
      t.datetime :sincronizado_em
      t.datetime :atualizacao_pedida_em
      t.jsonb :processos, null: false, default: []
      t.jsonb :recados, null: false, default: {}
      t.timestamps
    end
    add_index :portal_clientes, [:account_id, :advbox_customer_id], unique: true
    add_index :portal_clientes, [:account_id, :email], unique: true
  end
end
