# Telefone do cliente (do ADVBOX) pro link wa.me do resumo diário da equipe.
class AddTelefoneToPortalClientes < ActiveRecord::Migration[7.1]
  def change
    add_column :portal_clientes, :telefone, :string
  end
end
