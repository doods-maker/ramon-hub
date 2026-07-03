class LostReason < ApplicationRecord
  belongs_to :account

  validates :name, presence: true, uniqueness: { scope: :account_id }

  default_scope { order(:position, :id) }
end
