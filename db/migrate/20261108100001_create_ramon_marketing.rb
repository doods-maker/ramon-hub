# Área Marketing (spec 2026-11-07-marketing-trafego-design): o gasto da Meta ganha conjunto,
# objetivo, resultados e a origem (api | csv); custos lançados à mão; metas vindas do modelo.mjs;
# desempenho de cada peça publicada no Instagram.
class CreateRamonMarketing < ActiveRecord::Migration[7.1]
  def change
    gastos
    custos
    metas
    pecas
  end

  private

  def gastos
    change_table :ramon_meta_gastos, bulk: true do |t|
      t.string :adset_id
      t.string :adset_name
      t.string :objetivo
      t.bigint :conversas, default: 0
      t.bigint :leads_meta, default: 0
      t.string :origem, null: false, default: 'api'
    end
  end

  def custos
    create_table :ramon_marketing_custos do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :thesis, foreign_key: { on_delete: :nullify }, index: false
      t.references :user, index: false
      t.date :data, null: false
      t.decimal :valor, precision: 12, scale: 2, null: false
      t.string :categoria, null: false
      t.string :observacao
      t.timestamps
      t.index %i[account_id data]
    end
  end

  def metas
    create_table :ramon_marketing_metas do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.date :mes, null: false
      t.string :metrica, null: false
      t.decimal :valor, precision: 14, scale: 2, null: false
      t.timestamps
      t.index %i[account_id mes metrica], unique: true
    end
  end

  def pecas
    change_table :ramon_pecas, bulk: true do |t|
      t.integer :alcance
      t.integer :salvamentos
      t.integer :compartilhamentos
      t.integer :curtidas
      t.integer :comentarios
      t.datetime :metricas_em
    end
  end
end
