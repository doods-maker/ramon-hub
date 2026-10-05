# Painel do cliente (lado do escritório):
# - suspender acesso sem apagar nada (suspenso_em) e derrubar as sessões abertas
#   (sessao_chave entra na versão do cookie: trocar a chave invalida todas);
# - registro de acesso sobrevive à exclusão do cliente (Marco Civil art. 15: 6 meses)
#   com o CPF copiado na linha;
# - trilha de auditoria do hub (portal_eventos): quem fez o quê em qual cliente.
class AddSuspensaoEAuditoriaAoPortal < ActiveRecord::Migration[7.1]
  def change
    change_table :portal_clientes, bulk: true do |t|
      t.datetime :suspenso_em
      t.string :sessao_chave
    end
    add_column :portal_acessos, :cpf, :string

    create_table :portal_eventos do |t|
      t.bigint :portal_cliente_id
      t.bigint :user_id
      t.string :acao, null: false
      t.string :detalhe
      t.datetime :created_at, null: false
      t.index :portal_cliente_id
    end

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE portal_acessos SET cpf = portal_clientes.cpf
          FROM portal_clientes WHERE portal_clientes.id = portal_acessos.portal_cliente_id
        SQL
      end
    end
  end
end
