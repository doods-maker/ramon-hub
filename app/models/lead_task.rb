class LeadTask < ApplicationRecord
  KINDS = %w[follow_up document meeting other].freeze

  belongs_to :account
  belongs_to :lead
  belongs_to :user, optional: true

  validates :title, presence: true, length: { maximum: 255 }
  validates :kind, inclusion: { in: KINDS }
  validates :due_at, presence: true

  scope :open_tasks, -> { where(completed_at: nil) }
  scope :overdue, -> { open_tasks.where(due_at: ...Time.current) }
  scope :due_today, -> { open_tasks.where(due_at: Time.current.all_day) }

  after_create_commit :record_created_activity, :touch_lead
  after_update_commit :touch_lead

  def complete!(completing_user)
    update!(completed_at: Time.current)
    lead.lead_activities.create!(account: account, user: completing_user, kind: 'task_completed', to_value: title)
  end

  private

  def record_created_activity
    lead.lead_activities.create!(account: account, user: Current.user, kind: 'task_created', to_value: title)
  end

  def touch_lead
    lead.dispatch_task_update
  end
end
