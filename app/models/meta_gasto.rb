# Gasto diário por anúncio vindo do Gerenciador de Anúncios da Meta.
class MetaGasto < ApplicationRecord
  self.table_name = 'ramon_meta_gastos'

  belongs_to :account
end
