# Extrato nas duas grades (plano 2026-11-09-extrato-duas-grades, PR 2):
# - fator de qualidade do trimestre na meta do mês (modelo A; 1,0 = neutro); papel passa a aceitar 'hibrido';
# - Programa de Metas do híbrido (modelo B), um por trimestre, editável pelo gestor: regras = faixas do bônus do mês,
#   gás acima de N e constância do trimestre (paga no extrato do mês seguinte ao fim).
class CreateRamonProgramasMetas < ActiveRecord::Migration[7.1]
  def change
    add_column :ramon_metas_comerciais, :fator, :decimal, precision: 3, scale: 2, default: 1.0, null: false
    create_table :ramon_programas_metas do |t|
      t.references :account, null: false, foreign_key: true
      t.date :inicio, null: false
      t.date :fim, null: false
      t.jsonb :regras, null: false, default: {}
      t.timestamps
    end
  end
end
