# Casos de teste da IA: conversas-modelo por assistente, com critério do que é
# resposta boa, e as rodadas que rodam todos de uma vez (passou/falhou por caso).
# captain_tool_runs.source separa o que o teste pediu do que rodou de verdade —
# Execuções, Ferramentas e Visão geral filtram source = 'teste'.
class CreateRamonIaCasos < ActiveRecord::Migration[7.1]
  def change
    criar_casos
    criar_rodadas
    add_column :captain_tool_runs, :source, :string
  end

  private

  def criar_casos
    create_table :ramon_ia_casos do |t|
      t.bigint :account_id, null: false
      t.bigint :assistant_id, null: false
      t.string :codigo
      t.string :titulo, null: false
      t.string :grupo
      t.jsonb :mensagens, null: false, default: []
      t.jsonb :criterios, null: false, default: {}
      t.boolean :ativo, null: false, default: true
      t.string :origem, null: false, default: 'usuario'
      t.timestamps
      t.index [:account_id, :assistant_id]
      t.index [:assistant_id, :codigo], unique: true, where: 'codigo IS NOT NULL'
    end
  end

  def criar_rodadas
    create_table :ramon_ia_rodadas do |t|
      t.bigint :account_id, null: false
      t.bigint :assistant_id, null: false
      t.bigint :disparado_por_id
      t.string :status, null: false, default: 'fila'
      t.integer :total, null: false, default: 0
      t.integer :passou, null: false, default: 0
      t.integer :falhou, null: false, default: 0
      t.integer :duracao_ms
      t.text :erro
      t.jsonb :resultados, null: false, default: []
      t.timestamps
      t.index [:assistant_id, :created_at]
      # uma rodada por assistente por vez — o banco garante, não só o controller
      t.index :assistant_id, unique: true, where: "status IN ('fila', 'rodando')", name: 'idx_ramon_ia_rodadas_uma_ativa'
    end
  end
end
