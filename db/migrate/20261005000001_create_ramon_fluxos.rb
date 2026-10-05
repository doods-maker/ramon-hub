# Automações em fluxo (spec 2026-10-05): fluxo = desenho versionado; execução = uma
# passada por um lead/conversa, com trilha. Ensaio tem versao_id nulo (roda o rascunho).
class CreateRamonFluxos < ActiveRecord::Migration[7.1]
  def change
    create_table :ramon_fluxos do |t|
      t.bigint :account_id, null: false
      t.string :nome, null: false
      t.text :descricao
      t.string :gatilho_tipo
      t.boolean :ativo, null: false, default: false
      t.integer :limite_dia
      t.string :origem, null: false, default: 'usuario'
      t.string :sistema_chave
      t.string :modo, null: false, default: 'normal'
      t.jsonb :rascunho, null: false, default: {}
      t.bigint :versao_publicada_id
      t.datetime :ultimo_disparo_em
      t.bigint :created_by_id
      t.timestamps
      t.index [:account_id, :gatilho_tipo]
    end

    create_table :ramon_fluxo_versoes do |t|
      t.bigint :fluxo_id, null: false
      t.integer :numero, null: false
      t.jsonb :grafo, null: false, default: {}
      t.bigint :publicado_por_id
      t.datetime :created_at, null: false
      t.index [:fluxo_id, :numero], unique: true
    end

    create_table :ramon_fluxo_execucoes do |t|
      t.bigint :account_id, null: false
      t.bigint :fluxo_id, null: false
      t.bigint :versao_id
      t.string :alvo_type, null: false
      t.bigint :alvo_id, null: false
      t.string :status, null: false, default: 'rodando'
      t.boolean :ensaio, null: false, default: false
      t.string :no_atual
      t.datetime :retomar_em
      t.integer :tentativas, null: false, default: 0
      t.integer :profundidade, null: false, default: 0
      t.jsonb :contexto, null: false, default: {}
      t.jsonb :trilha, null: false, default: []
      t.text :erro
      t.timestamps
      t.index [:fluxo_id, :created_at]
      t.index [:fluxo_id, :alvo_type, :alvo_id], unique: true, name: 'index_ramon_fluxo_execucoes_unica_ativa',
                                                 where: "status IN ('rodando', 'esperando') AND NOT ensaio"
      t.index :retomar_em, name: 'index_ramon_fluxo_execucoes_retomar', where: "status = 'esperando'"
    end
  end
end
