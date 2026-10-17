# bi_leads v02 ganha a origem do anúncio; views novas do gasto e do rastro dos avisos da Meta.
# replace_view (CREATE OR REPLACE): bi_stage_transitions depende de bi_leads, e as colunas novas vão no fim.
class BiMetaViews < ActiveRecord::Migration[7.1]
  def up
    replace_view :bi_leads, version: 2
    create_view :bi_meta_gastos
    create_view :bi_meta_eventos
  end

  # bi_leads v1 tem menos colunas que a v2: replace_view nao desce, entao recria na ordem das dependencias.
  def down
    drop_view :bi_meta_eventos
    drop_view :bi_meta_gastos
    drop_view :bi_stage_transitions
    drop_view :bi_leads
    create_view :bi_leads, version: 1
    create_view :bi_stage_transitions, version: 1
  end
end
