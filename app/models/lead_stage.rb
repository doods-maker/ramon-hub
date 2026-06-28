class LeadStage < ApplicationRecord
  belongs_to :account
  has_many :leads, dependent: :restrict_with_exception

  validates :name, presence: true, uniqueness: { scope: :account_id }
  default_scope { order(:position) }
end
