class TriageAgent < ApplicationRecord
  PROVIDERS = %w[deepseek anthropic openai].freeze
  AREAS = %w[previdenciario trabalhista outro].freeze

  belongs_to :account
  has_many :lead_triages, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :system_prompt, presence: true
  validates :provider, inclusion: { in: PROVIDERS }
  validates :model, presence: true
  validates :area, inclusion: { in: AREAS }

  scope :active, -> { where(active: true) }
end
