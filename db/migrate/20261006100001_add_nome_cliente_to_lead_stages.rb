# Nome da etapa para o CLIENTE (portal do link mágico mostra "Seu caso está
# em: …" e a linha do tempo das etapas). Vazio = usa o nome interno.
class AddNomeClienteToLeadStages < ActiveRecord::Migration[7.1]
  def change
    add_column :lead_stages, :nome_cliente, :string
  end
end
