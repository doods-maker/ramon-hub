# Peticionamento pela pasta: petição nasce em conferência (sem tribunal/número) e guarda a leitura da pasta.
class PeticaoPelaPasta < ActiveRecord::Migration[7.1]
  def change
    change_column_null :ramon_peticoes, :tribunal, true
    add_column :ramon_peticoes, :pela_pasta, :boolean, default: false, null: false
    add_column :ramon_peticoes, :leitura, :jsonb, default: {}, null: false
    add_index :ramon_peticoes, %i[account_id drive_pasta_id], unique: true, where: 'pela_pasta',
                                                              name: 'index_ramon_peticoes_on_conta_e_pasta_unica'
  end
end
