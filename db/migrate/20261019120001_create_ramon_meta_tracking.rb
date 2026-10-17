# Rastreamento Meta no funil: avisos de conversão (um por lead e evento) e gasto diário por anúncio.
# `status` dos eventos: pendente | enviado | erro | ignorado.
class CreateRamonMetaTracking < ActiveRecord::Migration[7.1]
  def change
    eventos
    gastos
  end

  private

  def eventos
    create_table :ramon_meta_eventos do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :lead, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :evento, null: false
      t.string :event_id, null: false
      t.string :status, null: false, default: 'pendente'
      t.string :erro
      t.datetime :enviado_em
      t.datetime :ocorrido_em, null: false
      t.timestamps
      t.index %i[lead_id evento], unique: true
      t.index %i[account_id status]
    end
  end

  def gastos
    create_table :ramon_meta_gastos do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.date :data, null: false
      t.string :ad_id, null: false
      t.string :ad_name
      t.string :campaign_id
      t.string :campaign_name
      t.decimal :spend, precision: 12, scale: 2, default: 0
      t.bigint :impressions, default: 0
      t.bigint :clicks, default: 0
      t.timestamps
      t.index %i[account_id ad_id data], unique: true
    end
  end
end
