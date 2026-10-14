# bi_roteiro v02 (roteiro F5): aguarda_equipe some com o Perdido aprovado e entra limite_motivo (contrato que não saiu).
class UpdateBiRoteiroToV02 < ActiveRecord::Migration[7.1]
  def change
    update_view :bi_roteiro, version: 2, revert_to_version: 1
  end
end
