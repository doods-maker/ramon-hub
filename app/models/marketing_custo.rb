# Custo de marketing lançado à mão (aba Custos e metas). Sem tese = custo geral, rateado entre as teses no Metabase.
class MarketingCusto < ApplicationRecord
  self.table_name = 'ramon_marketing_custos'

  CATEGORIAS = %w[impulsionamento criativo ferramenta agencia equipe outro].freeze

  belongs_to :account
  belongs_to :thesis, optional: true
  belongs_to :user, optional: true

  validates :data, presence: true
  validates :valor, numericality: { greater_than: 0 }
  validates :categoria, inclusion: { in: CATEGORIAS }
end
