class LeadNote < ApplicationRecord
  belongs_to :account
  belongs_to :lead
  belongs_to :user, optional: true

  validates :body, presence: true

  default_scope { order(created_at: :asc) }
end
