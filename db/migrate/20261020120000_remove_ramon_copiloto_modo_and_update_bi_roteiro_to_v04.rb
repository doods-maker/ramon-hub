# Remove o modo antigo do copiloto (substituído pelo Perfil da IA) e passa bi_roteiro.modo a ler a Pausa da conversa.
class RemoveRamonCopilotoModoAndUpdateBiRoteiroToV04 < ActiveRecord::Migration[7.1]
  def change
    remove_column :inboxes, :ramon_copiloto_modo, :string
    update_view :bi_roteiro, version: 4, revert_to_version: 3
  end
end
