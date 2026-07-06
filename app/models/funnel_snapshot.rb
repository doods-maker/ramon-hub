class FunnelSnapshot < ApplicationRecord
  belongs_to :account
  belongs_to :lead_stage, optional: true
  belongs_to :thesis, optional: true
end
