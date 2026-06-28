class BenefitType < ApplicationRecord
  belongs_to :account
  has_many :leads, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :account_id }
  default_scope { order(:position) }
end
