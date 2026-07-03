class LeadStage < ApplicationRecord
  belongs_to :account
  has_many :leads, dependent: :restrict_with_exception

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :probability, numericality: { in: 0..100 }
  validates :stalled_after_days, numericality: { greater_than: 0 }, allow_nil: true
  default_scope { order(:position) }

  before_save :ensure_single_won_lost

  private

  def ensure_single_won_lost
    unset_flag_on_others(:is_won) if is_won? && (new_record? || will_save_change_to_is_won?)
    unset_flag_on_others(:is_lost) if is_lost? && (new_record? || will_save_change_to_is_lost?)
  end

  def unset_flag_on_others(flag)
    account.lead_stages.where.not(id: id).update_all(flag => false) # rubocop:disable Rails/SkipsModelValidations
  end
end
