# Honorário pela tabela do POP JUR-02 (decisão Eduardo 13/10/2026), linha online/tráfego.
# Tese não listada (BPC, acréscimo de 25%, maternidade, criadas na tela) fica fora da tabela:
# a IA não cita valor e o Dr. Ramon define.
class AddJur02ToTheses < ActiveRecord::Migration[7.1]
  JUR02 = {
    'Auxílio-acidente (B36)' => { pct: 30, n: 3, min: 3, base: 'sm' },
    'Auxílio por incapacidade temporária (auxílio-doença / B31)' => { pct: 30, n: nil, min: 1, base: 'sb' },
    'Aposentadoria por incapacidade permanente (invalidez / B32)' => { pct: 30, n: nil, min: 3, base: 'sb' }
  }.freeze

  def up
    add_column :theses, :honorario_minimo_qtd, :integer
    add_column :theses, :honorario_minimo_base, :string
    add_column :theses, :honorario_na_tabela, :boolean, default: false, null: false

    JUR02.each do |nome, v|
      execute <<~SQL.squish
        UPDATE theses SET honorario_percentual = #{v[:pct]},
          honorario_n_mensalidades = #{v[:n] || 'NULL'},
          honorario_minimo_qtd = #{v[:min]}, honorario_minimo_base = '#{v[:base]}',
          honorario_na_tabela = TRUE
        WHERE name = #{connection.quote(nome)}
      SQL
    end
  end

  def down
    remove_column :theses, :honorario_minimo_qtd
    remove_column :theses, :honorario_minimo_base
    remove_column :theses, :honorario_na_tabela
  end
end
