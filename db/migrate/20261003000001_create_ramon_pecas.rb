class CreateRamonPecas < ActiveRecord::Migration[7.1]
  # rubocop:disable Metrics/MethodLength
  def change
    create_table :ramon_pecas do |t|
      t.references :account, null: false, foreign_key: true
      t.string :slug, null: false
      t.date :rodada, null: false
      t.string :tipo, null: false
      t.string :estilo
      t.string :tese
      t.string :gancho, null: false
      t.jsonb :conteudo, null: false, default: {}
      t.text :legenda
      t.string :status, null: false, default: 'rascunho'
      t.jsonb :imagens, null: false, default: []
      t.integer :refazer_cards, array: true, null: false, default: []
      t.datetime :agendado_para
      t.datetime :montagem_iniciada_em
      t.datetime :publicacao_iniciada_em
      t.string :ig_media_id
      t.string :permalink
      t.text :erro
      t.text :nota_reprovacao
      t.string :notion_page_id
      t.string :drive_pasta_id
      t.timestamps
    end
    add_index :ramon_pecas, [:account_id, :slug], unique: true
    add_index :ramon_pecas, [:status, :agendado_para]
  end
  # rubocop:enable Metrics/MethodLength
end
