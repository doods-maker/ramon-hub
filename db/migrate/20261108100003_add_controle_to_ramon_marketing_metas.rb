# Metas sob controle do Eduardo: `ativa` liga/desliga todas no Metabase (nascem desligadas, inclusive as já
# subidas) e `editada_em` marca a meta alterada à mão no hub (subir um mensal.json novo avisa antes de desfazer).
class AddControleToRamonMarketingMetas < ActiveRecord::Migration[7.1]
  def up
    change_table :ramon_marketing_metas, bulk: true do |t|
      t.boolean :ativa, null: false, default: false
      t.datetime :editada_em
    end
    update_view :bi_marketing_metas, version: 2, revert_to_version: 1
  end

  def down
    update_view :bi_marketing_metas, version: 1, revert_to_version: 2
    change_table :ramon_marketing_metas, bulk: true do |t|
      t.remove :ativa, :editada_em
    end
  end
end
