class CreateBiRoteiro < ActiveRecord::Migration[7.1]
  def change
    create_view :bi_roteiro
  end
end
