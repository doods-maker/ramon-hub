# 2ª tarefa ADVBOX do envio: a secretária anexa o arquivo do Drive no ADVBOX.
class AddJuntadaPostIdToPortalEnvios < ActiveRecord::Migration[7.1]
  def change
    add_column :portal_envios, :juntada_post_id, :string
  end
end
