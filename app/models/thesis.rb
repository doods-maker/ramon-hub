class Thesis < ApplicationRecord
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
