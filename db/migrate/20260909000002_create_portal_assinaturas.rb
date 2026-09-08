class CreatePortalAssinaturas < ActiveRecord::Migration[7.1]
  def change
    create_table :portal_assinaturas do |t|
      t.references :portal_cliente, null: false, foreign_key: true
      t.string :doc_token, null: false
      t.string :signer_token
      t.string :nome
      t.string :status, null: false, default: 'pendente'
      t.datetime :assinado_em
      t.timestamps
    end
    add_index :portal_assinaturas, :doc_token, unique: true
  end
end
