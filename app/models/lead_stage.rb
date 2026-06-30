class LeadStage < ApplicationRecord
  belongs_to :account
  has_many :leads, dependent: :restrict_with_exception

  validates :name, presence: true, uniqueness: { scope: :account_id }
  default_scope { order(:position) }

  before_save :ensure_single_won_lost

  private

  def ensure_single_won_lost
    if is_won? && (new_record? || will_save_change_to_is_won?)
      account.lead_stages.where.not(id: id).update_all(is_won: false)
    end
    if is_lost? && (new_record? || will_save_change_to_is_lost?)
      account.lead_stages.where.not(id: id).update_all(is_lost: false)
    end
  end
end
