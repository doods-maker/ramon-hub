# Painel do Cliente: login vira CPF + senha (provisória de 6 dígitos gerada no
# hub, trocável pelo cliente). E-mail passa a ser opcional (só recuperação por código).
class AddSenhaToPortalClientes < ActiveRecord::Migration[7.1]
  def change
    add_column :portal_clientes, :senha_digest, :string
    change_column_null :portal_clientes, :email, true
    add_index :portal_clientes, [:account_id, :cpf], unique: true
  end
end
