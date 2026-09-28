# LGPD/Marco Civil do Painel do Cliente:
# - ia_consentimento: autorização (ou recusa) do cliente p/ a IA com servidor na China
#   organizar os documentos pedidos (LGPD art. 33, VIII); nil = ainda não respondeu;
# - portal_acessos: data/hora + IP de cada acesso, guardados 6 meses (Marco Civil art. 15).
class AddLgpdToPortal < ActiveRecord::Migration[7.1]
  def change
    add_column :portal_clientes, :ia_consentimento, :boolean # rubocop:disable Rails/ThreeStateBooleanColumn -- nil = ainda não respondeu

    create_table :portal_acessos do |t|
      t.bigint :portal_cliente_id, null: false
      t.string :ip
      t.datetime :created_at, null: false
      t.index :portal_cliente_id
    end
  end
end
