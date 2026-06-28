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

  def push_event_data
    {
      id: id,
      name: name,
      lead_stage_id: lead_stage_id,
      benefit_type_id: benefit_type_id,
      lead_priority_id: lead_priority_id,
      contact_id: contact_id,
      conversation_id: conversation_id,
      position: position
    }
  end
end
