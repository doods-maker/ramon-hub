# bi_leads v03: lead da LP com utm_source=meta passa a ter o ad_id (utm_content numérico).
# replace_view (CREATE OR REPLACE): bi_stage_transitions depende de bi_leads; mesmas colunas, só muda a expressão.
class BiMarketingViews < ActiveRecord::Migration[7.1]
  def up
    replace_view :bi_leads, version: 3
    update_view :bi_meta_gastos, version: 2, revert_to_version: 1
    create_view :bi_marketing_custos
    create_view :bi_marketing_metas
    create_view :bi_pecas
  end

  def down
    drop_view :bi_pecas
    drop_view :bi_marketing_metas
    drop_view :bi_marketing_custos
    update_view :bi_meta_gastos, version: 1, revert_to_version: 2
    replace_view :bi_leads, version: 2
  end
end
