# bi_roteiro v03: entra o grupo do teste A/B das opções em botões (opcoes_grupo), para comparar botões × texto.
class UpdateBiRoteiroToV03 < ActiveRecord::Migration[7.1]
  def change
    update_view :bi_roteiro, version: 3, revert_to_version: 2
  end
end
