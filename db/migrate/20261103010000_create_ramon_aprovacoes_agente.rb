# Pedidos de permissão da esteira de petições, respondidos pelo hub (ADR 0014).
class CreateRamonAprovacoesAgente < ActiveRecord::Migration[7.1]
  def change
    create_table :ramon_aprovacoes_agente do |t|
      t.string :caso
      t.string :ferramenta, null: false
      t.jsonb :entrada, null: false, default: {}
      t.string :status, null: false, default: 'pendente'
      t.bigint :decidida_por_id
      t.datetime :decidida_em
      t.timestamps
    end
    add_index :ramon_aprovacoes_agente, :status
  end
end
