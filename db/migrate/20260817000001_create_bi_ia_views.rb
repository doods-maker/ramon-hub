class CreateBiIaViews < ActiveRecord::Migration[7.1]
  def change
    create_view :bi_ia_rascunhos
    create_view :bi_ia_conversas
  end
end
