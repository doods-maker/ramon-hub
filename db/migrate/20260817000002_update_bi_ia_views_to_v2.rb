class UpdateBiIaViewsToV2 < ActiveRecord::Migration[7.1]
  def change
    update_view :bi_ia_rascunhos, version: 2, revert_to_version: 1
    update_view :bi_ia_conversas, version: 2, revert_to_version: 1
  end
end
