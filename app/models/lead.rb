class Lead < ApplicationRecord
  belongs_to :account
  belongs_to :lead_stage
  belongs_to :contact, optional: true
  belongs_to :conversation, optional: true
  belongs_to :benefit_type, optional: true
  belongs_to :lead_priority, optional: true
  belongs_to :thesis, optional: true
  belongs_to :sdr, class_name: 'User', optional: true
  belongs_to :closer, class_name: 'User', optional: true
  has_many :lead_activities, dependent: :destroy_async
  has_many :lead_notes, dependent: :destroy_async
  has_many :lead_tasks, dependent: :destroy_async, inverse_of: :lead

  validates :lead_stage, presence: true
  default_scope { order(:lead_stage_id, :position, :id) }

  before_save :track_stage_cycle

  after_create_commit :dispatch_create_event
  after_update_commit :dispatch_update_event
  after_create_commit :record_created_activity
  after_update_commit :record_change_activities

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity
  def push_event_data
    {
      id: id,
      name: name,
      lead_stage_id: lead_stage_id,
      benefit_type_id: benefit_type_id,
      lead_priority_id: lead_priority_id,
      thesis_id: thesis_id,
      contact_id: contact_id,
      conversation_id: conversation_id,
      position: position,
      value: value,
      source: source,
      stage_name: lead_stage&.name,
      stage_color: lead_stage&.color,
      benefit_type_name: benefit_type&.name,
      lead_priority_name: lead_priority&.name,
      thesis_name: thesis&.name,
      sdr_name: sdr&.name,
      closer_name: closer&.name,
      contact_name: contact&.name
    }.merge(cadence_event_data)
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity

  def stalled?
    return false if lead_stage&.stalled_after_days.blank? || stage_entered_at.blank?

    stage_entered_at < lead_stage.stalled_after_days.days.ago
  end

  def dispatch_task_update
    dispatch_update_event
  end

  private

  def cadence_event_data
    {
      stage_entered_at: stage_entered_at,
      won_at: won_at,
      lost_at: lost_at,
      stalled: stalled?,
      open_tasks_count: lead_tasks.open_tasks.size,
      next_task_due_at: lead_tasks.open_tasks.minimum(:due_at),
      contact_phone: contact&.phone_number
    }
  end

  def track_stage_cycle
    return unless will_save_change_to_lead_stage_id? || new_record?

    self.stage_entered_at = Time.current
    apply_stage_timestamps(LeadStage.find_by(id: lead_stage_id))
  end

  def apply_stage_timestamps(stage)
    won = stage&.is_won
    lost = stage&.is_lost
    self.won_at = won ? existing_or_now(won_at) : nil
    self.lost_at = lost ? existing_or_now(lost_at) : nil
    self.lost_reason = nil unless lost
  end

  def existing_or_now(current)
    current || Time.current
  end

  def dispatch_create_event
    Rails.configuration.dispatcher.dispatch(Events::Types::LEAD_CREATED, Time.zone.now, lead: self)
  end

  def dispatch_update_event
    Rails.configuration.dispatcher.dispatch(Events::Types::LEAD_UPDATED, Time.zone.now, lead: self)
  end

  def record_created_activity
    lead_activities.create!(account: account, user: Current.user, kind: 'created', to_value: source)
  end

  def record_change_activities
    record_change('lead_stage_id', 'stage_changed') { |id| LeadStage.find_by(id: id)&.name }
    record_change('sdr_id', 'sdr_changed') { |id| User.find_by(id: id)&.name }
    record_change('closer_id', 'closer_changed') { |id| User.find_by(id: id)&.name }
    record_change('lead_priority_id', 'priority_changed') { |id| LeadPriority.find_by(id: id)&.name }
    record_change('thesis_id', 'thesis_changed') { |id| Thesis.find_by(id: id)&.name }
    record_change('value', 'value_changed') { |v| v&.to_s }
  end

  def record_change(attribute, kind)
    return unless saved_changes.key?(attribute)

    old_raw, new_raw = saved_changes[attribute]
    lead_activities.create!(
      account: account, user: Current.user, kind: kind,
      from_value: yield(old_raw), to_value: yield(new_raw)
    )
  end
end
