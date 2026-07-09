class LeadTriage < ApplicationRecord
  STATUSES = %w[pending running done awaiting_human error].freeze
  VIABILITIES = %w[alta media baixa].freeze
  KIT_STATUSES = %w[pending running ready error].freeze

  belongs_to :account
  belongs_to :lead
  belongs_to :triage_agent, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :viability, inclusion: { in: VIABILITIES }, allow_nil: true
  validates :kit_status, inclusion: { in: KIT_STATUSES }

  after_update_commit :broadcast_lead

  private

  # o painel do lead recebe o resumo da triagem pelo broadcast lead.updated
  def broadcast_lead
    lead.dispatch_task_update
  end
end
