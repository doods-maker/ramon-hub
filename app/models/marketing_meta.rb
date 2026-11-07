# Meta mensal do comercial vinda do modelo.mjs (fonte única dos números). Gravada só por Ramon::MetasDoModelo.
class MarketingMeta < ApplicationRecord
  self.table_name = 'ramon_marketing_metas'

  belongs_to :account
end
