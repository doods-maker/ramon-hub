class LeadNote < ApplicationRecord
  belongs_to :account
  belongs_to :lead
  belongs_to :user, optional: true

  validates :body, presence: true, length: { maximum: 1000 }

  default_scope { order(created_at: :asc) }

  after_create_commit :record_note_activity

  private

  def record_note_activity
    lead.lead_activities.create!(
      account: account, user: Current.user, kind: 'note_added', to_value: body.to_s.truncate(60)
    )
  end
end
