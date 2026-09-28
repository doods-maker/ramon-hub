# Métricas do piloto: quem entrou e quem voltou (dias distintos com acesso).
class AddAcessoToPortalClientes < ActiveRecord::Migration[7.1]
  def change
    add_column :portal_clientes, :ultimo_acesso_em, :datetime
    add_column :portal_clientes, :dias_acesso, :integer, default: 0, null: false
  end
end
