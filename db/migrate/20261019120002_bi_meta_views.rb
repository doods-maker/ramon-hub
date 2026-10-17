# bi_leads v02 ganha a origem do anúncio; views novas do gasto e do rastro dos avisos da Meta.
# replace_view (CREATE OR REPLACE): bi_stage_transitions depende de bi_leads, e as colunas novas vão no fim.
class BiMetaViews < ActiveRecord::Migration[7.1]
  def change
    replace_view :bi_leads, version: 2, revert_to_version: 1
    create_view :bi_meta_gastos
    create_view :bi_meta_eventos
  end
end
