class Thesis < ApplicationRecord
  # Padrão do escritório em TODAS as teses: 30% dos atrasados + 3 benefícios.
  # Aplicado na criação pela tela (ThesesController#create), não como default
  # de coluna: teses existentes e criadas por seed/spec ficam como estão.
  HONORARIO_PADRAO = { honorario_percentual: 30, honorario_n_mensalidades: 3 }.freeze

  belongs_to :account
  has_many :thesis_items, -> { order(:position) }, dependent: :destroy, inverse_of: :thesis
  has_many :leads, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :honorario_percentual,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 },
            allow_nil: true
  validates :honorario_n_mensalidades,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 },
            allow_nil: true
  default_scope { order(:position) }
end
