class Lead < ApplicationRecord
  belongs_to :account
  belongs_to :lead_stage
  belongs_to :contact, optional: true
  belongs_to :conversation, optional: true
  belongs_to :benefit_type, optional: true
  belongs_to :lead_priority, optional: true
  belongs_to :sdr, class_name: 'User', optional: true
  belongs_to :closer, class_name: 'User', optional: true

  validates :lead_stage, presence: true
  default_scope { order(:lead_stage_id, :position, :id) }

  after_create_commit :dispatch_create_event
  after_update_commit :dispatch_update_event

  def push_event_data # rubocop:disable Metrics/CyclomaticComplexity
    {
      id: id,
      name: name,
      lead_stage_id: lead_stage_id,
      benefit_type_id: benefit_type_id,
      lead_priority_id: lead_priority_id,
      contact_id: contact_id,
      conversation_id: conversation_id,
      position: position,
      value: value,
      source: source,
      stage_name: lead_stage&.name,
      stage_color: lead_stage&.color,
      benefit_type_name: benefit_type&.name,
      lead_priority_name: lead_priority&.name,
      sdr_name: sdr&.name,
      closer_name: closer&.name,
      contact_name: contact&.name
    }
  end

  private

  def dispatch_create_event
    Rails.configuration.dispatcher.dispatch(Events::Types::LEAD_CREATED, Time.zone.now, lead: self)
  end

  def dispatch_update_event
    Rails.configuration.dispatcher.dispatch(Events::Types::LEAD_UPDATED, Time.zone.now, lead: self)
  end
end
