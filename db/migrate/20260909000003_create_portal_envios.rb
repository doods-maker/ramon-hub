class CreatePortalEnvios < ActiveRecord::Migration[7.1]
  def change
    create_table :portal_envios do |t|
      t.references :portal_cliente, null: false, foreign_key: true
      t.bigint :lawsuit_id
      t.bigint :solicitacao_post_id
      t.string :item
      t.string :drive_file_id
      t.string :advbox_post_id
      t.timestamps
    end
    add_index :portal_envios, [:portal_cliente_id, :solicitacao_post_id], name: 'portal_envios_cliente_solicitacao_idx'
  end
end
