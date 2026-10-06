# Extrato da variável FECHADO (regulamento §6): passado o prazo, a apuração é
# definitiva — guarda o extrato de cada pessoa como foi apurado e nunca mais
# recalcula. leads.contrato_cancelado_em = quando um contrato limpo saiu de
# Fechado (base do desconto na apuração seguinte, §5.2).
class CreateRamonExtratosFechados < ActiveRecord::Migration[7.1]
  def change
    create_table :ramon_extratos_fechados do |t|
      t.references :account, null: false
      t.references :user, null: false
      t.string :papel, null: false
      t.date :competencia, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :fechado_em, null: false
      t.timestamps
    end
    add_index :ramon_extratos_fechados, [:account_id, :competencia, :user_id, :papel], unique: true, name: 'idx_ramon_extratos_fechados_unico'
    add_column :leads, :contrato_cancelado_em, :datetime
  end
end
