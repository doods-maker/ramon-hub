class AddHonorarioToTheses < ActiveRecord::Migration[7.1]
  def up
    add_column :theses, :honorario_percentual, :decimal, precision: 5, scale: 2
    add_column :theses, :honorario_n_mensalidades, :integer

    # Semente da casa p/ contas existentes: auxílio-acidente = 30% + 3 mensalidades.
    # Contas novas recebem via theses_seed.yml (Task 3).
    execute <<~SQL.squish
      UPDATE theses SET honorario_percentual = 30, honorario_n_mensalidades = 3
      WHERE name = 'Auxílio-acidente (B36)' AND honorario_percentual IS NULL
    SQL
  end

  def down
    remove_column :theses, :honorario_percentual
    remove_column :theses, :honorario_n_mensalidades
  end
end
