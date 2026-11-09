# Sobras do extrato (decisões do Eduardo 09/11/2026):
# - leads.reuniao_pela_ia: a reunião registrada foi marcada pela IA (tarefa sem criador) — não paga o SDR;
# - ramon_fatores_trimestre: fator de qualidade calculado no 1º dia do trimestre e guardado (extrato estável), com a
#   conta (base) para o gestor ver;
# - ramon_metas_comerciais.fator vira opcional: vazio = vale o calculado; preenchido = o gestor corrigiu.
class AddFatorTrimestreEReuniaoPelaIa < ActiveRecord::Migration[7.1]
  def up
    add_column :leads, :reuniao_pela_ia, :boolean, default: false, null: false
    change_column_null :ramon_metas_comerciais, :fator, true
    change_column_default :ramon_metas_comerciais, :fator, from: 1.0, to: nil
    execute 'UPDATE ramon_metas_comerciais SET fator = NULL WHERE fator = 1.0'
    create_table :ramon_fatores_trimestre do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :papel, null: false
      t.date :inicio, null: false
      t.decimal :fator, precision: 3, scale: 2, null: false
      t.jsonb :base, null: false, default: {}
      t.timestamps
    end
    add_index :ramon_fatores_trimestre, [:account_id, :user_id, :papel, :inicio], unique: true, name: 'index_ramon_fatores_trimestre_unico'
  end

  def down
    drop_table :ramon_fatores_trimestre
    execute 'UPDATE ramon_metas_comerciais SET fator = 1.0 WHERE fator IS NULL'
    change_column_default :ramon_metas_comerciais, :fator, from: nil, to: 1.0
    change_column_null :ramon_metas_comerciais, :fator, false
    remove_column :leads, :reuniao_pela_ia
  end
end
